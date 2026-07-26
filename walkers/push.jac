import from walkers.ingest_push { do_ingest_push }
import from walkers.integrate { do_integrate }
import from walkers.publish { do_publish }

"""The one endpoint the CLI actually calls. Chains ingest -> integrate ->
publish as direct function calls (never nested walker spawns - that's what
silently broke integrate's blast-radius context earlier). Everything upstream
of this (ingest_push, integrate, publish, blast_radius) stays independently
callable for testing/debugging - this just adds the single-call path a real
developer's CLI needs, matching the original Synqit's one-shot `synqit push`.
"""
def do_push(project: str, intent: str, base_sha: str, changes: list[dict], submitter: str, max_hops: int) -> dict {
    ingested = do_ingest_push(project, intent, base_sha, changes, submitter);
    if "error" in ingested {
        return ingested;
    }

    push_id: str = ingested["push_id"] as str;

    integrated = do_integrate(push_id, max_hops);
    if "error" in integrated {
        return integrated;
    }
    if integrated["status"] != "integrated" {
        return integrated;
    }

    return do_publish(push_id);
}

"""Authenticated."""
walker push {
    has project: str;
    has intent: str;
    has base_sha: str;
    has changes: list[dict] = [];
    has submitter: str = "";
    has max_hops: int = 2;

    can run with Root entry {
        report do_push(self.project, self.intent, self.base_sha, self.changes, self.submitter, self.max_hops);
    }
}
