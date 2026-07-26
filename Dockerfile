FROM python:3.12-slim

WORKDIR /app

# jac-client is what compiles the browser bundle; without it `jac start`
# serves the REST API but no UI.
RUN pip install --no-cache-dir jaclang byllm requests jac-client

COPY . .

# Installs the npm dependencies declared in jac.toml (bun is fetched into
# .jac/bin on first run). Editing jac.toml alone installs nothing.
RUN jac install

EXPOSE 8080

CMD ["jac", "start", "main.jac", "--port", "8080"]
