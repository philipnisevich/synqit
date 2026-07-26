import from ".ui.card" { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ".ui.button" { Button }
import from ".ui.badge" { Badge }
import from ".ui.input" { Input }
import from ".ui.textarea" { Textarea }
import from ".ui.field" { Field, FieldLabel }
import from ".ui.spinner" { Spinner }
import from ".ui.dialog" { Dialog, DialogTrigger, DialogContent, DialogHeader, DialogTitle }
import from ".ui.table" { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from "@jac/runtime" { useParams, Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Add01Icon, ArrowLeft01Icon, RefreshIcon, RocketIcon }
sv import from ..services.synqitService {
    list_pushes, submit_push, integrate_push, seed, get_project_rpc,
    PushView, ProjectView, ActionResult,
}

def get_status_variant(status: str) -> str {
    if status == "published" or status == "integrated" {
        return "default";
    } elif status == "needs_human" or status == "integration_incomplete" {
        return "destructive";
    }
    return "secondary";
}

def:pub ProjectDetail() -> JsxElement {
    has pushes: list[PushView] = [];
    has project: ProjectView | None = None;
    has loading: bool = True;
    has error: str = "";
    has notice: str = "";
    has notice_ok: bool = True;
    has busy: str = "";
    has dialog_open: bool = False;
    has intent: str = "";
    has base_sha: str = "";
    has submitter: str = "";
    has paths_input: str = "";
    has submitting: bool = False;
    has submit_error: str = "";

    params: any = useParams();
    project_name: str = (params["name"] or "") as str;

    async def refresh() -> None {
        pushes = await list_pushes(project_name);
        project = await get_project_rpc(project_name);
    }

    async can with entry {
        try {
            await refresh();
        } except Exception as e {
            error = str(e);
        }
        loading = False;
    }

    # Populates File nodes and Imports edges from the live GitHub branch.
    # Until this runs, blast_radius has nothing to walk, so an integration
    # would be handed an empty workspace.
    async def handle_seed() -> None {
        current: ProjectView | None = project;
        if current is None or current.repository == "" {
            notice_ok = False;
            notice = "This project has no repository set.";
            return;
        }
        parts: list[str] = current.repository.split("/");
        if len(parts) < 2 {
            notice_ok = False;
            notice = "Repository must be in owner/repo form, got: " + current.repository;
            return;
        }
        busy = "seed";
        notice = "";
        try {
            owner: str = parts[len(parts) - 2];
            repo: str = parts[len(parts) - 1];
            branch: str = current.branch if current.branch else "main";
            result: ActionResult = await seed(project_name, owner, repo, branch);
            notice_ok = result.ok;
            notice = f"Seeded from {owner}/{repo}@{branch}." if result.ok else result.message;
            await refresh();
        } except Exception as e {
            notice_ok = False;
            notice = str(e);
        }
        busy = "";
    }

    # Runs the same integrate -> publish chain `synqit push` drives through
    # walker push: an LLM call scoped to the push's blast radius, then a real
    # commit to GitHub. Can take a minute.
    async def handle_integrate(push_id: str) -> None {
        busy = push_id;
        notice = "";
        try {
            max_hops: int = 2;
            result: ActionResult = await integrate_push(push_id, max_hops);
            notice_ok = result.ok;
            if result.ok {
                notice = "Published to GitHub " + result.detail[:7] + ". " + result.message;
            } elif result.detail != "" {
                notice = result.message + " " + result.detail;
            } else {
                notice = result.message;
            }
            await refresh();
        } except Exception as e {
            notice_ok = False;
            notice = str(e);
        }
        busy = "";
    }

    async def handle_submit() -> None {
        if intent == "" or base_sha == "" {
            submit_error = "Intent and base SHA are required.";
            return;
        }
        submitting = True;
        submit_error = "";
        try {
            touched_paths: list[str] = [p.strip() for p in paths_input.split(",") if p.strip() != ""];
            result: ActionResult = await submit_push(project_name, intent, base_sha, submitter, touched_paths);
            if not result.ok {
                submit_error = result.message;
                submitting = False;
                return;
            }
            await refresh();
            dialog_open = False;
            intent = "";
            base_sha = "";
            submitter = "";
            paths_input = "";
        } except Exception as e {
            submit_error = str(e);
        }
        submitting = False;
    }

    if loading {
        return <div className="flex items-center justify-center min-h-[400px]">
            <Spinner />
        </div>;
    }

    return <div className="flex flex-col gap-6 pt-6 pb-6 pl-6 pr-6">
        <div className="flex items-center gap-3">
            <Link to="/">
                <Button variant="ghost" size="icon">
                    <HugeiconsIcon icon={ArrowLeft01Icon} strokeWidth={2} className="size-4" />
                </Button>
            </Link>
            <div className="flex-1">
                <h1 className="text-2xl font-semibold tracking-tight">{project_name}</h1>
                <p className="text-sm text-muted-foreground mt-1 font-mono">
                    {project != None and project.repository or "Push requests"}
                    {project != None and project.head != "" and f" @ {project.head[:7]}" or ""}
                </p>
            </div>
            <Button variant="outline" onClick={handle_seed} disabled={busy != ""}>
                {busy == "seed" and <Spinner className="size-4" /> or <HugeiconsIcon icon={RefreshIcon} strokeWidth={2} className="size-4" />}
                Seed from GitHub
            </Button>
            <Dialog open={dialog_open} onOpenChange={lambda (v: bool) { dialog_open = v; }}>
                <DialogTrigger asChild={True}>
                    <Button>
                        <HugeiconsIcon icon={Add01Icon} strokeWidth={2} className="size-4" />
                        New Push
                    </Button>
                </DialogTrigger>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Submit Push Request</DialogTitle>
                    </DialogHeader>
                    <div className="flex flex-col gap-4 pt-2">
                        {submit_error != "" and
                            <div className="text-sm text-destructive bg-destructive/10 rounded-md pt-3 pb-3 pl-4 pr-4">
                                {submit_error}
                            </div>
                        or None}
                        <Field>
                            <FieldLabel htmlFor="push-intent">Feature Intent</FieldLabel>
                            <Textarea
                                id="push-intent"
                                placeholder="Describe what this push should accomplish..."
                                value={intent}
                                onChange={lambda (e: any) { intent = e.target.value as str; }}
                                disabled={submitting}
                                rows={3}
                            />
                        </Field>
                        <Field>
                            <FieldLabel htmlFor="push-sha">Base SHA</FieldLabel>
                            <Input
                                id="push-sha"
                                placeholder="abc1234"
                                value={base_sha}
                                onChange={lambda (e: any) { base_sha = e.target.value as str; }}
                                disabled={submitting}
                            />
                        </Field>
                        <Field>
                            <FieldLabel htmlFor="push-submitter">Submitter</FieldLabel>
                            <Input
                                id="push-submitter"
                                placeholder="your-username"
                                value={submitter}
                                onChange={lambda (e: any) { submitter = e.target.value as str; }}
                                disabled={submitting}
                            />
                        </Field>
                        <Field>
                            <FieldLabel htmlFor="push-paths">Touched Paths (comma-separated)</FieldLabel>
                            <Input
                                id="push-paths"
                                placeholder="src/main.py, src/utils.py"
                                value={paths_input}
                                onChange={lambda (e: any) { paths_input = e.target.value as str; }}
                                disabled={submitting}
                            />
                        </Field>
                        <div className="flex justify-end gap-3 pt-2">
                            <Button
                                variant="outline"
                                onClick={lambda { dialog_open = False; }}
                                disabled={submitting}
                            >
                                Cancel
                            </Button>
                            <Button onClick={handle_submit} disabled={submitting}>
                                {submitting and <Spinner className="size-4" /> or None}
                                {submitting and "Submitting..." or "Submit Push"}
                            </Button>
                        </div>
                    </div>
                </DialogContent>
            </Dialog>
        </div>

        {error != "" and
            <div className="text-sm text-destructive bg-destructive/10 rounded-md pt-3 pb-3 pl-4 pr-4">{error}</div>
        or None}

        {notice != "" and
            <div className={"text-sm rounded-md border border-emerald-500/40 bg-emerald-500/10 pt-3 pb-3 pl-4 pr-4" if notice_ok else "text-sm text-destructive bg-destructive/10 rounded-md pt-3 pb-3 pl-4 pr-4"}>
                {notice}
            </div>
        or None}

        <Card>
            <CardHeader>
                <CardTitle>Push Requests</CardTitle>
                <CardDescription>
                    {len(pushes) == 0 and "No push requests yet." or f"{len(pushes)} push request(s)"}
                </CardDescription>
            </CardHeader>
            <CardContent>
                {len(pushes) == 0 and
                    <div className="flex flex-col items-center gap-3 pt-8 pb-8 text-center">
                        <p className="text-sm text-muted-foreground">No push requests yet. Submit the first one.</p>
                    </div>
                or
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Intent</TableHead>
                                <TableHead>Submitter</TableHead>
                                <TableHead>Base SHA</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead>Created</TableHead>
                                <TableHead></TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {for push in pushes {
                                if push != None {
                                    <TableRow key={push.id}>
                                        <TableCell className="max-w-[280px] font-medium">
                                            <div className="truncate">{push.intent}</div>
                                            {push.summary != "" and
                                                <div className="text-xs text-muted-foreground mt-1">{push.summary}</div>
                                            or None}
                                            {push.touched_label != "" and
                                                <div className="text-xs font-mono text-muted-foreground mt-1 truncate">
                                                    {push.touched_label}
                                                </div>
                                            or None}
                                            {push.deleted_label != "" and
                                                <div className="text-xs font-mono text-destructive mt-1 truncate">
                                                    {"deleted: " + push.deleted_label}
                                                </div>
                                            or None}
                                        </TableCell>
                                        <TableCell className="text-muted-foreground">{push.submitter or "-"}</TableCell>
                                        <TableCell className="font-mono text-xs">{push.base_sha[:8]}</TableCell>
                                        <TableCell>
                                            <Badge variant={get_status_variant(push.status)}>
                                                {push.status}
                                            </Badge>
                                        </TableCell>
                                        <TableCell className="text-xs text-muted-foreground">
                                            {push.created_at != "" and push.created_at[:10] or "-"}
                                        </TableCell>
                                        <TableCell>
                                            {push.status == "pending" and
                                                <Button
                                                    size="sm"
                                                    variant="outline"
                                                    onClick={lambda { handle_integrate(push.id); }}
                                                    disabled={busy != ""}
                                                >
                                                    {busy == push.id and <Spinner className="size-4" /> or <HugeiconsIcon icon={RocketIcon} strokeWidth={2} className="size-4" />}
                                                    Integrate & Publish
                                                </Button>
                                            or None}
                                        </TableCell>
                                    </TableRow>
                                }
                            }}
                        </TableBody>
                    </Table>
                }
            </CardContent>
        </Card>
    </div>;
}
