import from ".ui.card" { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter }
import from ".ui.button" { Button }
import from ".ui.input" { Input }
import from ".ui.field" { Field, FieldLabel }
import from ".ui.spinner" { Spinner }
sv import from ..services.synqitService { create_project_rpc, ActionResult }

def:pub NewProject() -> JsxElement {
    has name: str = "";
    has repository: str = "";
    has branch: str = "main";
    has submitting: bool = False;
    has error: str = "";

    async def handle_submit() -> None {
        if name == "" or repository == "" {
            error = "Project name and repository are required.";
            return;
        }
        submitting = True;
        error = "";
        try {
            result: ActionResult = await create_project_rpc(name, repository, branch);
            if not result.ok {
                error = result.message;
                submitting = False;
                return;
            }
            # Full reload rather than navigate("/app"): the client runtime caches
            # reader responses for 60s and the Dashboard's list_projects call
            # is a reader, so a soft navigation can land on a stale empty list.
            window.location.href = "/app";
        } except Exception as e {
            error = str(e);
            submitting = False;
        }
    }

    return <div className="flex items-center justify-center min-h-[calc(100vh-4rem)] pt-6 pb-6 pl-6 pr-6">
        <Card className="w-full max-w-lg">
            <CardHeader>
                <CardTitle className="text-xl">New Project</CardTitle>
                <CardDescription>
                    Connect a repository to start managing shared pushes.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="flex flex-col gap-4">
                    {error != "" and
                        <div className="text-sm text-destructive bg-destructive/10 rounded-md pt-3 pb-3 pl-4 pr-4">
                            {error}
                        </div>
                    or None}
                    <Field>
                        <FieldLabel htmlFor="proj-name">Project Name</FieldLabel>
                        <Input
                            id="proj-name"
                            placeholder="my-project"
                            value={name}
                            onChange={lambda (e: any) { name = e.target.value as str; }}
                            disabled={submitting}
                        />
                    </Field>
                    <Field>
                        <FieldLabel htmlFor="proj-repo">Repository</FieldLabel>
                        <Input
                            id="proj-repo"
                            placeholder="owner/repo"
                            value={repository}
                            onChange={lambda (e: any) { repository = e.target.value as str; }}
                            disabled={submitting}
                        />
                        <p className="text-xs text-muted-foreground">
                            owner/repo form, not a full URL - seeding and publishing split on the slash.
                        </p>
                    </Field>
                    <Field>
                        <FieldLabel htmlFor="proj-branch">Branch</FieldLabel>
                        <Input
                            id="proj-branch"
                            placeholder="main"
                            value={branch}
                            onChange={lambda (e: any) { branch = e.target.value as str; }}
                            disabled={submitting}
                        />
                    </Field>
                </div>
            </CardContent>
            <CardFooter className="flex justify-end gap-3">
                <Button
                    variant="outline"
                    onClick={lambda { window.location.href = "/"; }}
                    disabled={submitting}
                >
                    Cancel
                </Button>
                <Button
                    onClick={handle_submit}
                    disabled={submitting}
                >
                    {submitting and <Spinner className="size-4" /> or None}
                    {submitting and "Creating..." or "Create Project"}
                </Button>
            </CardFooter>
        </Card>
    </div>;
}
