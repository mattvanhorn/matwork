# Graph Report - .  (2026-07-15)

## Corpus Check
- Corpus is ~49,413 words - fits in a single context window. You may not need a graph.

## Summary
- 481 nodes · 534 edges · 81 communities (40 shown, 41 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 43 edges (avg confidence: 0.88)
- Token cost: 0 input · 125,789 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Matwork Project Rules & Design Rationale|Matwork Project Rules & Design Rationale]]
- [[_COMMUNITY_Gyms Domain Implementation (Task BriefsReports)|Gyms Domain Implementation (Task Briefs/Reports)]]
- [[_COMMUNITY_Ash Actions, Changes & Validations|Ash Actions, Changes & Validations]]
- [[_COMMUNITY_AshPostgres Migration Snapshot (auth ext 2)|AshPostgres Migration Snapshot (auth ext 2)]]
- [[_COMMUNITY_AshPostgres Migration Snapshot (invite)|AshPostgres Migration Snapshot (invite)]]
- [[_COMMUNITY_AshPostgres Migration Snapshot (membership)|AshPostgres Migration Snapshot (membership)]]
- [[_COMMUNITY_AshAuthentication Strategies & Policies|AshAuthentication Strategies & Policies]]
- [[_COMMUNITY_AshPostgres Migration Snapshot (auth ext 1)|AshPostgres Migration Snapshot (auth ext 1)]]
- [[_COMMUNITY_AshPostgres Migration Snapshot (auth ext 1b)|AshPostgres Migration Snapshot (auth ext 1b)]]
- [[_COMMUNITY_Ash Framework Skill Index & Core Reference|Ash Framework Skill Index & Core Reference]]
- [[_COMMUNITY_Embedded Usage-Rules Guideline Blocks|Embedded Usage-Rules Guideline Blocks]]
- [[_COMMUNITY_AshPhoenix.Form Reference|AshPhoenix.Form Reference]]
- [[_COMMUNITY_StalwartUI Core Components|StalwartUI Core Components]]
- [[_COMMUNITY_ActiveMember Policy Check & Ash Query Filtering|ActiveMember Policy Check & Ash Query Filtering]]
- [[_COMMUNITY_MatworkWeb Web Module Macros|MatworkWeb Web Module Macros]]
- [[_COMMUNITY_Test Generator (Matwork.Generator)|Test Generator (Matwork.Generator)]]
- [[_COMMUNITY_Ash Relationships & Foreign Keys|Ash Relationships & Foreign Keys]]
- [[_COMMUNITY_AshOban Triggers Reference|AshOban Triggers Reference]]
- [[_COMMUNITY_AshAshOban Migration & Multitenancy Workflow|Ash/AshOban Migration & Multitenancy Workflow]]
- [[_COMMUNITY_Repo & Data Case Test Support|Repo & Data Case Test Support]]
- [[_COMMUNITY_Mix Project Config|Mix Project Config]]
- [[_COMMUNITY_Gyms Domain Module & Resource Tests|Gyms Domain Module & Resource Tests]]
- [[_COMMUNITY_AcceptInvite Change Module|AcceptInvite Change Module]]
- [[_COMMUNITY_Magic Link Mailer|Magic Link Mailer]]
- [[_COMMUNITY_Telemetry Setup|Telemetry Setup]]
- [[_COMMUNITY_AshOban Programmatic Triggers|AshOban Programmatic Triggers]]
- [[_COMMUNITY_Layouts Component|Layouts Component]]
- [[_COMMUNITY_Auth Controller|Auth Controller]]
- [[_COMMUNITY_CanInviteRole Policy Check|CanInviteRole Policy Check]]
- [[_COMMUNITY_CanRemoveMembership Policy Check|CanRemoveMembership Policy Check]]
- [[_COMMUNITY_Frontend JS Assets|Frontend JS Assets]]
- [[_COMMUNITY_OTP Application Supervisor|OTP Application Supervisor]]
- [[_COMMUNITY_Oban Migration|Oban Migration]]
- [[_COMMUNITY_Auth Extension Migration 1|Auth Extension Migration 1]]
- [[_COMMUNITY_Auth Extension Migration 2|Auth Extension Migration 2]]
- [[_COMMUNITY_Gym Resource Migration|Gym Resource Migration]]
- [[_COMMUNITY_Membership Resource Migration|Membership Resource Migration]]
- [[_COMMUNITY_Invite Resource Migration|Invite Resource Migration]]
- [[_COMMUNITY_AshOban Error Handling Reference|AshOban Error Handling Reference]]
- [[_COMMUNITY_Heroicons Build Plugin|Heroicons Build Plugin]]
- [[_COMMUNITY_CreateOwnerMembership Change|CreateOwnerMembership Change]]
- [[_COMMUNITY_Local Claude SettingsPermissions|Local Claude Settings/Permissions]]
- [[_COMMUNITY_Error HTML Handler|Error HTML Handler]]
- [[_COMMUNITY_Error JSON Handler|Error JSON Handler]]
- [[_COMMUNITY_Page Controller|Page Controller]]
- [[_COMMUNITY_LiveView Auth Hook|LiveView Auth Hook]]
- [[_COMMUNITY_AshPhoenix Usage Rules|AshPhoenix Usage Rules]]
- [[_COMMUNITY_Ash Postgres Extensions Snapshot|Ash Postgres Extensions Snapshot]]
- [[_COMMUNITY_User Resource|User Resource]]
- [[_COMMUNITY_StalwartUI Extraction Discipline Rule|StalwartUI Extraction Discipline Rule]]
- [[_COMMUNITY_Error HTML Test|Error HTML Test]]
- [[_COMMUNITY_Error JSON Test|Error JSON Test]]
- [[_COMMUNITY_Page Controller Test|Page Controller Test]]
- [[_COMMUNITY_Page HTML View|Page HTML View]]
- [[_COMMUNITY_Gym Resource Module|Gym Resource Module]]
- [[_COMMUNITY_Invite Resource Module|Invite Resource Module]]
- [[_COMMUNITY_Membership Resource Module|Membership Resource Module]]
- [[_COMMUNITY_Matwork App Module|Matwork App Module]]
- [[_COMMUNITY_Accounts Domain Module|Accounts Domain Module]]
- [[_COMMUNITY_Auth Overrides|Auth Overrides]]
- [[_COMMUNITY_Endpoint|Endpoint]]
- [[_COMMUNITY_Gettext|Gettext]]
- [[_COMMUNITY_Router|Router]]
- [[_COMMUNITY_Conn Case Test Support|Conn Case Test Support]]
- [[_COMMUNITY_JSCSS Guidelines Note|JS/CSS Guidelines Note]]
- [[_COMMUNITY_Phoenix v1.8 Guidelines Note|Phoenix v1.8 Guidelines Note]]
- [[_COMMUNITY_UIUX Guidelines Note|UI/UX Guidelines Note]]
- [[_COMMUNITY_Brand Mark (logo.svg)|Brand Mark (logo.svg)]]
- [[_COMMUNITY_robots.txt|robots.txt]]

## God Nodes (most connected - your core abstractions)
1. `Ash Framework Skill (Index)` - 39 edges
2. `MatworkWeb.CoreComponents` - 12 edges
3. `Ash Actions Reference` - 11 edges
4. `Invite Resource (Matwork.Gyms.Invite)` - 11 edges
5. `MatworkWeb` - 10 edges
6. `AshAuthentication Usage Rules` - 10 edges
7. `BJJ Instructor Platform POC Design Document` - 10 edges
8. `Membership Resource (Matwork.Gyms.Membership)` - 10 edges
9. `Matwork.MixProject` - 8 edges
10. `AshPostgres Usage Rules` - 7 edges

## Surprising Connections (you probably didn't know these)
- `Attribute-Based Multitenancy on gym_id` --rationale_for--> `Membership Resource (Matwork.Gyms.Membership)`  [EXTRACTED]
  docs/superpowers/plans/2026-07-14-milestone-0-session-2-gym-membership-invite.md → lib/matwork/gyms/membership.ex
- `Attribute-Based Multitenancy on gym_id` --rationale_for--> `Invite Resource (Matwork.Gyms.Invite)`  [EXTRACTED]
  docs/superpowers/plans/2026-07-14-milestone-0-session-2-gym-membership-invite.md → lib/matwork/gyms/invite.ex
- `Token-Possession Trust Model` --rationale_for--> `Invite Resource (Matwork.Gyms.Invite)`  [EXTRACTED]
  docs/superpowers/plans/2026-07-14-milestone-0-session-2-gym-membership-invite.md → lib/matwork/gyms/invite.ex
- `Token-Possession Trust Model` --rationale_for--> `AcceptInvite Change`  [EXTRACTED]
  docs/superpowers/plans/2026-07-14-milestone-0-session-2-gym-membership-invite.md → lib/matwork/gyms/membership/changes/accept_invite.ex
- `Upsert-Based Membership Reactivation` --rationale_for--> `AcceptInvite Change`  [EXTRACTED]
  docs/superpowers/plans/2026-07-14-milestone-0-session-2-gym-membership-invite.md → lib/matwork/gyms/membership/changes/accept_invite.ex

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Action Modification Pipeline (Validations, Preparations, Changes, Atomic Changes)** — references_actions_validations, references_actions_preparations, references_actions_changes, references_actions_atomic_changes [INFERRED 0.75]
- **AshAuthentication Strategies** — references_ash_authentication_password_strategy, references_ash_authentication_magic_link_strategy, references_ash_authentication_api_key_strategy, references_ash_authentication_oauth2_strategy [EXTRACTED 1.00]
- **Ash Policy Authorization System** — references_authorization_policies, references_authorization_bypass_policies, references_authorization_field_policies, references_authorization_policy_checks [EXTRACTED 1.00]
- **AshPhoenix.Form usage docs** — references_form_integration, references_error_handling, references_nested_forms, references_union_forms, references_debugging_form_submissions [INFERRED 0.85]
- **Ash.Query building and filtering docs** — references_querying_data, references_query_filter, references_exist_expressions [INFERRED 0.85]
- **AshOban background job configuration docs** — references_defining_triggers, references_scheduled_actions, references_setting_up_ash_oban, references_multi_tenancy_support, references_triggering_jobs_programmatically, references_working_with_actors [INFERRED 0.85]
- **Attribute-Multitenant (gym_id) Resources** — docs_design_membership, docs_design_invite, docs_design_course, docs_design_coursesection, docs_design_lesson, docs_design_video, docs_design_plan, docs_design_subscription, docs_design_stripecustomer [EXTRACTED 1.00]
- **Tenant-Independent Global Resources** — docs_design_user, docs_design_token, docs_design_gym, docs_design_webhookevent [EXTRACTED 1.00]
- **Paywall / Content-Gating Authorization Flow** — docs_design_lesson, docs_design_membership, docs_design_subscription, docs_design_mux, docs_design_authorization_policies [INFERRED 0.85]
- **Gym create -> invite -> accept_invite demoable flow** — gyms_gym_gym, gyms_membership_membership, gyms_invite_invite, changes_accept_invite_acceptinvite, checks_active_member_activemember [EXTRACTED 1.00]
- **Post-review privilege-escalation hardening fixes** — checks_can_remove_membership_canremovemembership, checks_can_invite_role_caninviterole, changes_accept_invite_acceptinvite, sdd_task_7_report [INFERRED 0.85]

## Communities (81 total, 41 thin omitted)

### Community 0 - "Matwork Project Rules & Design Rationale"
Cohesion: 0.09
Nodes (35): Migrations & Codegen Rule, Money & External Services Iron Rules, Matwork Project Overview & Design-Doc Authority Rule, Matwork Stack Summary, Tenancy & Authorization Iron Rules, Testing Requirements (allow/deny policy paths, tenancy isolation), Development Workflow Rules, Accounts Domain (+27 more)

### Community 1 - "Gyms Domain Implementation (Task Briefs/Reports)"
Cohesion: 0.20
Nodes (27): AcceptInvite Change, CreateOwnerMembership Change, GenerateToken Change, ActiveMember Policy Check, CanInviteRole Policy Check, CanRemoveMembership Policy Check, Attribute-Based Multitenancy on gym_id, Token-Possession Trust Model (+19 more)

### Community 2 - "Ash Actions, Changes & Validations"
Cohesion: 0.12
Nodes (19): Ash Actions Reference, Atomic Changes, Ash Changes, Custom Change Modules (Ash.Resource.Change), Custom Modules vs Anonymous Functions, Custom Validation Modules (Ash.Resource.Validation), Ash Error Classes, Ash Preparations (+11 more)

### Community 3 - "AshPostgres Migration Snapshot (auth ext 2)"
Cohesion: 0.12
Nodes (16): attributes, base_filter, check_constraints, create_table_options, custom_indexes, custom_statements, has_create_action, hash (+8 more)

### Community 4 - "AshPostgres Migration Snapshot (invite)"
Cohesion: 0.12
Nodes (16): attributes, base_filter, check_constraints, create_table_options, custom_indexes, custom_statements, has_create_action, hash (+8 more)

### Community 5 - "AshPostgres Migration Snapshot (membership)"
Cohesion: 0.12
Nodes (16): attributes, base_filter, check_constraints, create_table_options, custom_indexes, custom_statements, has_create_action, hash (+8 more)

### Community 6 - "AshAuthentication Strategies & Policies"
Cohesion: 0.13
Nodes (17): AshAuthentication Usage Rules, API Key Strategy, Confirmation Add-on, Log Out Everywhere Add-on, Magic Link Strategy, OAuth2 Strategy, Password Strategy, AshAuthentication Tokens (+9 more)

### Community 7 - "AshPostgres Migration Snapshot (auth ext 1)"
Cohesion: 0.12
Nodes (16): attributes, base_filter, check_constraints, create_table_options, custom_indexes, custom_statements, has_create_action, hash (+8 more)

### Community 8 - "AshPostgres Migration Snapshot (auth ext 1b)"
Cohesion: 0.12
Nodes (16): attributes, base_filter, check_constraints, create_table_options, custom_indexes, custom_statements, has_create_action, hash (+8 more)

### Community 9 - "Ash Framework Skill Index & Core Reference"
Cohesion: 0.20
Nodes (16): Ash Framework Skill (Index), mix ash.gen.* tasks, Ash Advanced Features Reference, Manual Relationships (Ash.Resource.ManualRelationship), Multiple Repos / Read Replicas, Ash Core Reference, Ash Framework Core Philosophy, AshPostgres Usage Rules (+8 more)

### Community 10 - "Embedded Usage-Rules Guideline Blocks"
Cohesion: 0.14
Nodes (15): Embedded Elixir Guidelines Block, Embedded Phoenix HTML Guidelines Block, Embedded Phoenix LiveView Guidelines Block, Embedded Phoenix Guidelines Block, AGENTS.md Project Guidelines (mix precommit, Req over HTTPoison/Tesla), Elixir Core Usage Rules (usage_rules:elixir), OTP Usage Rules (usage_rules:otp), usage_rules Mix Tool (+7 more)

### Community 11 - "AshPhoenix.Form Reference"
Cohesion: 0.15
Nodes (15): AshPhoenix domain form_to_* code interface, AshPhoenix.Form, AshPhoenix.Form.add_form/2, AshPhoenix.Form.for_create/3, AshPhoenix.Form.for_update/3, AshPhoenix.Form.submit/2, AshPhoenix.Form.validate/2, AshPhoenix.FormData.Error protocol (+7 more)

### Community 12 - "StalwartUI Core Components"
Cohesion: 0.17
Nodes (3): MatworkWeb.CoreComponents, input(), translate_error()

### Community 13 - "ActiveMember Policy Check & Ash Query Filtering"
Cohesion: 0.18
Nodes (8): Ash.Query module, exists/2 query expression, Ash.Query.filter/2 macro, Matwork.Gyms.Checks.ActiveMember, Ash Exist Expressions Reference (stub), Ash Query Filter Reference (stub), require Ash.Query needed since filter/2 is a macro, Ash Querying Data Reference (stub)

### Community 14 - "MatworkWeb Web Module Macros"
Cohesion: 0.29
Nodes (8): MatworkWeb, controller(), html(), html_helpers(), live_component(), live_view(), static_paths(), verified_routes()

### Community 15 - "Test Generator (Matwork.Generator)"
Cohesion: 0.29
Nodes (9): Ash.Generator, Ash.Test utilities, Ash Testing Reference (stub), Globally unique identity values prevent concurrent test deadlocks, Matwork.Generator, gym(), invite(), membership() (+1 more)

### Community 16 - "Ash Relationships & Foreign Keys"
Cohesion: 0.22
Nodes (9): manage_relationship change/argument, Polymorphic relationships via Ash.Type.Union, Ash relationships DSL (belongs_to/has_one/has_many/many_to_many), AshPhoenix.Form.remove_form/2, AshPostgres references (foreign key) DSL, AshPostgres Foreign Keys Reference (stub), FK on_delete/on_update bypass resource logic (DB-level only), AshPhoenix Nested Forms Reference (stub) (+1 more)

### Community 17 - "AshOban Triggers Reference"
Cohesion: 0.22
Nodes (9): AshOban extension, config :ash_oban, :actor_persister, AshOban.PersistActor behaviour, AshOban scheduled_actions DSL, AshOban trigger DSL, AshOban Defining Triggers Reference (stub), AshOban Scheduled Actions Reference (stub), Setting Up AshOban Reference (stub) (+1 more)

### Community 18 - "Ash/AshOban Migration & Multitenancy Workflow"
Cohesion: 0.25
Nodes (9): AshOban list_tenants configuration, AshPostgres schema-based multitenancy (manage_tenant), mix ash.codegen, mix ash.migrate, mix ash_postgres.migrate --tenants, Ash Migrations Reference (stub), --dev migration workflow avoids premature migration naming, AshOban Multi-Tenancy Support Reference (stub) (+1 more)

### Community 20 - "Mix Project Config"
Cohesion: 0.33
Nodes (6): Matwork.MixProject, aliases(), deps(), elixirc_paths(), project(), usage_rules()

### Community 21 - "Gyms Domain Module & Resource Tests"
Cohesion: 0.25
Nodes (4): Matwork.Gyms.GymTest, Matwork.Gyms.InviteTest, Matwork.Gyms.MembershipTest, Matwork.Gyms

### Community 22 - "AcceptInvite Change Module"
Cohesion: 0.53
Nodes (5): Matwork.Gyms.Membership.Changes.AcceptInvite, apply_invite(), change(), finalize_invite(), mark_invite_accepted()

### Community 23 - "Magic Link Mailer"
Cohesion: 0.40
Nodes (4): Matwork.Mailer, Matwork.Accounts.User.Senders.SendMagicLinkEmail, body(), send()

### Community 24 - "Telemetry Setup"
Cohesion: 0.40
Nodes (3): MatworkWeb.Telemetry, init(), periodic_measurements()

### Community 25 - "AshOban Programmatic Triggers"
Cohesion: 0.50
Nodes (5): change run_oban_trigger/1, AshOban.run_trigger/2-3, AshOban.run_triggers/2, AshOban.schedule/3, AshOban Triggering Jobs Programmatically Reference (stub)

### Community 38 - "AshOban Error Handling Reference"
Cohesion: 0.50
Nodes (4): AshOban Usage Rules, AshOban Debugging and Error Handling Reference, AshOban.Errors.CancelJob, AshOban.Errors.SnoozeJob

### Community 39 - "Heroicons Build Plugin"
Cohesion: 0.50
Nodes (3): fs, path, plugin

### Community 46 - "AshPhoenix Usage Rules"
Cohesion: 0.67
Nodes (3): AshPhoenix Usage Rules, AshPhoenix.Form, AshPhoenix.LiveView

## Knowledge Gaps
- **148 isolated node(s):** `allow`, `csrfToken`, `liveSocket`, `plugin`, `fs` (+143 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **41 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Ash Framework Skill (Index)` connect `Ash Framework Skill Index & Core Reference` to `Ash Actions, Changes & Validations`, `AshOban Error Handling Reference`, `AshAuthentication Strategies & Policies`, `AshPhoenix.Form Reference`, `ActiveMember Policy Check & Ash Query Filtering`, `AshPhoenix Usage Rules`, `Test Generator (Matwork.Generator)`, `Ash Relationships & Foreign Keys`, `AshOban Triggers Reference`, `Ash/AshOban Migration & Multitenancy Workflow`, `AshOban Programmatic Triggers`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Why does `Ash Actions Reference` connect `Ash Actions, Changes & Validations` to `Ash Framework Skill Index & Core Reference`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `Ash Testing Reference (stub)` connect `Test Generator (Matwork.Generator)` to `Ash Framework Skill Index & Core Reference`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **What connects `allow`, `csrfToken`, `liveSocket` to the rest of the system?**
  _164 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Matwork Project Rules & Design Rationale` be split into smaller, more focused modules?**
  _Cohesion score 0.0907563025210084 - nodes in this community are weakly interconnected._
- **Should `Ash Actions, Changes & Validations` be split into smaller, more focused modules?**
  _Cohesion score 0.12280701754385964 - nodes in this community are weakly interconnected._
- **Should `AshPostgres Migration Snapshot (auth ext 2)` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._