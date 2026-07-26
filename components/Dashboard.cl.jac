import from ".ui.card" { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ".ui.button" { Button }
import from ".ui.badge" { Badge }
import from ".ui.spinner" { Spinner }
import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Add01Icon, Folder01Icon }
sv import from ..services.synqitService { list_projects, server_status, ProjectView, ServerStatus }

def:pub Dashboard() -> JsxElement {
    has projects: list[ProjectView] = [];
    has loading: bool = True;
    has error: str = "";
    has missing: str = "";

    async can with entry {
        try {
            projects = await list_projects();
            status: ServerStatus = await server_status();
            if not status.ready {
                missing = status.missing_label;
            }
        } except Exception as e {
            error = str(e);
        }
        loading = False;
    }

    if loading {
        return <div className="flex items-center justify-center min-h-[400px]">
            <Spinner />
        </div>;
    }

    return <div className="flex flex-col gap-6 pt-6 pb-6 pl-6 pr-6">
        <div className="flex items-center justify-between">
            <div>
                <h1 className="text-2xl font-semibold tracking-tight">Projects</h1>
                <p className="text-sm text-muted-foreground mt-1">
                    Manage your shared source control projects.
                </p>
            </div>
            <Link to="/new-project">
                <Button>
                    <HugeiconsIcon icon={Add01Icon} strokeWidth={2} className="size-4" />
                    New Project
                </Button>
            </Link>
        </div>

        {error != "" and <div className="text-sm text-destructive bg-destructive/10 rounded-md pt-3 pb-3 pl-4 pr-4">{error}</div> or None}

        {missing != "" and
            <div className="text-sm rounded-md border border-amber-500/40 bg-amber-500/10 pt-3 pb-3 pl-4 pr-4">
                <p className="font-medium">This server is missing {missing}.</p>
                <p className="text-muted-foreground mt-1">
                    Projects and push requests still work. Seeding, integration, and publishing
                    stay disabled until these are set in the server environment.
                </p>
            </div>
        or None}

        {len(projects) == 0 and
            <div className="flex min-h-[400px] items-center justify-center">
                <div className="flex flex-col items-center gap-4 text-center">
                    <div className="rounded-full bg-muted pt-4 pb-4 pl-4 pr-4">
                        <HugeiconsIcon icon={Folder01Icon} strokeWidth={2} className="size-8 text-muted-foreground" />
                    </div>
                    <div>
                        <p className="text-sm font-medium">No projects yet</p>
                        <p className="text-sm text-muted-foreground mt-1">Create your first project to get started.</p>
                    </div>
                    <Link to="/new-project">
                        <Button variant="outline">
                            <HugeiconsIcon icon={Add01Icon} strokeWidth={2} className="size-4" />
                            Create Project
                        </Button>
                    </Link>
                </div>
            </div>
        or
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {for p in projects {
                    if p != None {
                        <Link to={f"/project/{p.name}"} key={p.id}>
                            <Card className="hover:shadow-md transition-shadow cursor-pointer">
                                <CardHeader>
                                    <div className="flex items-start justify-between">
                                        <div className="flex flex-col gap-1">
                                            <CardTitle className="text-base">{p.name}</CardTitle>
                                            <CardDescription className="text-xs font-mono truncate max-w-[200px]">
                                                {p.repository}
                                            </CardDescription>
                                        </div>
                                        <Badge variant="outline">{p.branch}</Badge>
                                    </div>
                                </CardHeader>
                                <CardContent>
                                    <div className="flex items-center justify-between gap-2">
                                        <p className="text-xs text-muted-foreground">
                                            {p.created_at != "" and f"Created {p.created_at[:10]}" or "Recently created"}
                                        </p>
                                        {p.head != "" and
                                            <span className="font-mono text-xs text-muted-foreground">{p.head[:7]}</span>
                                        or
                                            <span className="text-xs text-muted-foreground">not seeded</span>
                                        }
                                    </div>
                                </CardContent>
                            </Card>
                        </Link>
                    }
                }}
            </div>
        }
    </div>;
}
