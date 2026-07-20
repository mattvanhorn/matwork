defmodule Matwork.Media.VideoTest do
  use Matwork.DataCase, async: true

  import Mox
  import Matwork.Generator

  alias Matwork.Media
  alias Matwork.Platform.SystemActor

  setup :verify_on_exit!

  @system %SystemActor{}

  describe "create_direct_upload/2" do
    test "an instructor starts an upload; Mux gets the tenant as passthrough" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      Matwork.Platform.MuxMock
      |> expect(:create_direct_upload, fn %{passthrough: passthrough} ->
        assert passthrough == gym.id
        {:ok, %{id: "upload_xyz", url: "https://storage.example/put"}}
      end)

      assert {:ok, {video, "https://storage.example/put"}} =
               Media.create_direct_upload("Armbar", actor: instructor, tenant: gym.id)

      assert video.mux_upload_id == "upload_xyz"
      assert video.status == :pending_upload
      assert video.uploaded_by_id == instructor.id
    end

    test "a student cannot start an upload" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      # Mux stub with no expectation — a forbidden create must never reach Mux.
      stub(Matwork.Platform.MuxMock, :create_direct_upload, fn _ ->
        flunk("Mux must not be called for a forbidden upload")
      end)

      assert {:error, %Ash.Error.Forbidden{}} =
               Media.create_direct_upload("Nope", actor: student, tenant: gym.id)
    end
  end

  describe "mark_* transitions (system actor only)" do
    test "mark_video_ready sets asset/playback/duration and status" do
      gym = generate(gym())
      video = generate(video(gym: gym))

      {:ok, ready} =
        Media.mark_video_ready(
          video,
          %{mux_asset_id: "asset_1", mux_playback_id: "pb_1", duration_seconds: 42},
          actor: @system,
          tenant: gym.id
        )

      assert ready.status == :ready
      assert ready.mux_asset_id == "asset_1"
      assert ready.mux_playback_id == "pb_1"
      assert ready.duration_seconds == 42
    end

    test "a normal manager cannot run mark_video_ready" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      video = generate(video(gym: gym))

      assert {:error, %Ash.Error.Forbidden{}} =
               Media.mark_video_ready(video, %{mux_asset_id: "a"}, actor: owner, tenant: gym.id)
    end
  end

  describe "read" do
    test "get_video_by_upload_id finds within the tenant" do
      gym = generate(gym())
      video = generate(video(gym: gym, mux_upload_id: "upload_find_me"))

      {:ok, found} =
        Media.get_video_by_upload_id("upload_find_me", actor: %SystemActor{}, tenant: gym.id)

      assert found.id == video.id
    end

    test "tenancy isolation: a manager in gym A cannot read gym B's video" do
      gym_a = generate(gym())
      manager_a = generate(user())
      generate(membership(gym: gym_a, user: manager_a, role: :instructor))

      gym_b = generate(gym())
      video_b = generate(video(gym: gym_b))

      # Read-policy denials are filtered rather than raised as Forbidden
      # (config :ash, policies: [no_filter_static_forbidden_reads?: false]),
      # so a denied get_by looks like a NotFound — same pattern as
      # Curriculum.Course's read-visibility deny tests (see course_test.exs).
      assert {:error, %Ash.Error.Invalid{}} =
               Media.get_video(video_b.id, actor: manager_a, tenant: gym_b.id)
    end
  end
end
