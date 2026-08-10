-- ============================================================
-- AI Agent Workflow Builder
-- Migration: 001_initial_schema
-- ============================================================

-- ------------------------------------------------------------
-- 1. Organizations
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,

    quota_calls_allowed INTEGER NOT NULL DEFAULT 1000,
    quota_calls_used INTEGER NOT NULL DEFAULT 0,
    quota_period_start DATE NOT NULL DEFAULT CURRENT_DATE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT organizations_name_not_blank
        CHECK (length(trim(name)) > 0),

    CONSTRAINT organizations_quota_allowed_nonnegative
        CHECK (quota_calls_allowed >= 0),

    CONSTRAINT organizations_quota_used_nonnegative
        CHECK (quota_calls_used >= 0)
);


-- ------------------------------------------------------------
-- 2. Organization members
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.org_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    org_id UUID NOT NULL
        REFERENCES public.organizations(id)
        ON DELETE CASCADE,

    user_id UUID NOT NULL,

    role TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT org_members_role_check
        CHECK (role IN ('owner', 'editor', 'viewer')),

    CONSTRAINT org_members_unique_user_per_org
        UNIQUE (org_id, user_id)
);


-- ------------------------------------------------------------
-- 3. Workflows
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    org_id UUID NOT NULL
        REFERENCES public.organizations(id)
        ON DELETE CASCADE,

    name TEXT NOT NULL,
    description TEXT,

    created_by UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT workflows_name_not_blank
        CHECK (length(trim(name)) > 0)
);


-- ------------------------------------------------------------
-- 4. Workflow steps
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workflow_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workflow_id UUID NOT NULL
        REFERENCES public.workflows(id)
        ON DELETE CASCADE,

    position INTEGER NOT NULL,

    name TEXT NOT NULL,

    type TEXT NOT NULL,

    config JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT workflow_steps_position_nonnegative
        CHECK (position >= 0),

    CONSTRAINT workflow_steps_type_check
        CHECK (
            type IN (
                'llm_call',
                'http_request',
                'db_write',
                'notify',
                'conditional_branch',
                'approval_gate'
            )
        ),

    CONSTRAINT workflow_steps_name_not_blank
        CHECK (length(trim(name)) > 0),

    CONSTRAINT workflow_steps_unique_position
        UNIQUE (workflow_id, position)
);


-- ------------------------------------------------------------
-- 5. Workflow triggers
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workflow_triggers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workflow_id UUID NOT NULL
        REFERENCES public.workflows(id)
        ON DELETE CASCADE,

    type TEXT NOT NULL,

    config JSONB NOT NULL DEFAULT '{}'::jsonb,

    enabled BOOLEAN NOT NULL DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT workflow_triggers_type_check
        CHECK (
            type IN (
                'manual',
                'webhook',
                'scheduled',
                'database_event'
            )
        )
);


-- ------------------------------------------------------------
-- 6. Workflow runs
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workflow_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workflow_id UUID NOT NULL
        REFERENCES public.workflows(id)
        ON DELETE CASCADE,

    trigger_type TEXT NOT NULL,

    status TEXT NOT NULL DEFAULT 'pending',

    created_by UUID,

    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    error TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT workflow_runs_status_check
        CHECK (
            status IN (
                'pending',
                'running',
                'paused',
                'completed',
                'failed'
            )
        ),

    CONSTRAINT workflow_runs_trigger_type_check
        CHECK (
            trigger_type IN (
                'manual',
                'webhook',
                'scheduled',
                'database_event'
            )
        )
);


-- ------------------------------------------------------------
-- 7. Step runs
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.step_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workflow_run_id UUID NOT NULL
        REFERENCES public.workflow_runs(id)
        ON DELETE CASCADE,

    workflow_step_id UUID NOT NULL
        REFERENCES public.workflow_steps(id)
        ON DELETE CASCADE,

    status TEXT NOT NULL DEFAULT 'pending',

    input JSONB,
    output JSONB,

    error TEXT,

    attempt_count INTEGER NOT NULL DEFAULT 0,

    approved_by UUID,
    approved_at TIMESTAMPTZ,

    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT step_runs_status_check
        CHECK (
            status IN (
                'pending',
                'running',
                'paused',
                'completed',
                'failed'
            )
        ),

    CONSTRAINT step_runs_attempt_count_nonnegative
        CHECK (attempt_count >= 0),

    CONSTRAINT step_runs_unique_step_per_run
        UNIQUE (workflow_run_id, workflow_step_id)
);


-- ------------------------------------------------------------
-- 8. Indexes
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_org_members_user_id
    ON public.org_members(user_id);

CREATE INDEX IF NOT EXISTS idx_org_members_org_id
    ON public.org_members(org_id);

CREATE INDEX IF NOT EXISTS idx_workflows_org_id
    ON public.workflows(org_id);

CREATE INDEX IF NOT EXISTS idx_workflow_steps_workflow_id
    ON public.workflow_steps(workflow_id);

CREATE INDEX IF NOT EXISTS idx_workflow_triggers_workflow_id
    ON public.workflow_triggers(workflow_id);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow_id
    ON public.workflow_runs(workflow_id);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_status
    ON public.workflow_runs(status);

CREATE INDEX IF NOT EXISTS idx_step_runs_workflow_run_id
    ON public.step_runs(workflow_run_id);

CREATE INDEX IF NOT EXISTS idx_step_runs_status
    ON public.step_runs(status);


-- ------------------------------------------------------------
-- 9. Aggregation view required by assignment
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW public.organization_usage_this_month AS
SELECT
    o.id AS organization_id,
    o.name AS organization_name,

    COUNT(DISTINCT wr.id) AS workflow_runs_this_month,

    COUNT(
        DISTINCT CASE
            WHEN wr.status = 'completed'
            THEN wr.id
        END
    ) AS completed_runs_this_month,

    COUNT(
        CASE
            WHEN ws.type IN ('llm_call', 'http_request')
            THEN sr.id
        END
    ) AS external_step_calls_this_month

FROM public.organizations o

LEFT JOIN public.workflows w
    ON w.org_id = o.id

LEFT JOIN public.workflow_runs wr
    ON wr.workflow_id = w.id
    AND wr.created_at >= date_trunc('month', CURRENT_TIMESTAMP)

LEFT JOIN public.step_runs sr
    ON sr.workflow_run_id = wr.id

LEFT JOIN public.workflow_steps ws
    ON ws.id = sr.workflow_step_id

GROUP BY
    o.id,
    o.name;