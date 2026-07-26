"""Synqit entry point.

Server context is the default, so the service import below is what boots the
graph, loads .env, and registers both endpoint families: `/function/<name>`
for the browser client and `/walker/<name>` for the `synqit` CLI. The `cl`
block holds the browser app.
"""

import from services.synqitService {
    ServerStatus, ProjectView, PushView, ActionResult,
    server_status, list_projects, create_project_rpc, get_project_rpc,
    list_pushes, submit_push, run_push, integrate_push, seed,
    blast_radius_for,
}

# The CLI talks to this server over REST, not through a client stub, so no
# `sv import` anywhere names these walkers. Importing each one by name in the
# entry module is what publishes `POST /walker/<name>` - importing only the
# module that imports them is not enough (verified: 404 until named here).
import from walkers.project { create_project, get_project }
import from walkers.ingest_push { ingest_push }
import from walkers.seed_project { seed_project }
import from walkers.blast_radius { blast_radius }
import from walkers.integrate { integrate }
import from walkers.publish { publish }
import from walkers.push { push }

cl {
    import ".styles.global.css";

    import from .components.Dashboard { Dashboard }
    import from .components.NewProject { NewProject }
    import from .components.ProjectDetail { ProjectDetail }
    import from "@jac/runtime" { Router, Routes, Route, Navigate }

    def:pub app() -> JsxElement {
        return <Router>
            <Routes>
                <Route path="/" element={<Dashboard />} />
                <Route path="/new-project" element={<NewProject />} />
                <Route path="/project/:name" element={<ProjectDetail />} />
                <Route path="*" element={<Navigate to="/" />} />
            </Routes>
        </Router>;
    }
}
