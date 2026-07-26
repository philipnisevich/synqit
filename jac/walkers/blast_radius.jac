import from nodes { PushRequest, File, Touches, Imports }

"""Pure context-gathering walker. Given a push, BFS outward from its touched
files along Imports edges - both directions, since a file that imports a
changed file (a caller) and a file the changed file itself imports (a
dependency) are both relevant context - up to max_hops. Read-only: never
mutates the graph, never flags a conflict, never calls needs_human. That
judgment belongs entirely to the `integrate` walker's LLM call downstream -
this walker only answers "what should it look at."
"""

obj BlastFile {
    has path: str;
    has content: str;
    has distance: int;
}

walker blast_radius {
    has push_id: str;
    has max_hops: int = 2;
    has reports: list[list[BlastFile]] = [];

    can run with Root entry {
        push = jobj(self.push_id);
        if not isinstance(push, PushRequest) {
            report [];
            disengage;
        }

        start_files: list[File] = [push ->:Touches:->][?:File];

        distance: dict[str, int] = {};
        node_by_id: dict[str, File] = {};
        for f in start_files {
            distance[jid(f)] = 0;
            node_by_id[jid(f)] = f;
        }

        frontier: list[File] = start_files;
        hop: int = 0;
        while hop < self.max_hops and frontier {
            next_frontier: list[File] = [];
            for f in frontier {
                outgoing: list[File] = [f ->:Imports:->];
                incoming: list[File] = [f <-:Imports:<-];
                for n in outgoing + incoming {
                    nid: str = jid(n);
                    if nid not in distance {
                        distance[nid] = hop + 1;
                        node_by_id[nid] = n;
                        next_frontier.append(n);
                    }
                }
            }
            frontier = next_frontier;
            hop += 1;
        }

        results: list[BlastFile] = [];
        for nid in distance.keys() {
            f: File = node_by_id[nid];
            results.append(BlastFile(path=f.path, content=f.content, distance=distance[nid]));
        }
        results.sort(key=lambda r: BlastFile : r.distance);

        report results;
    }
}
