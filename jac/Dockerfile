FROM python:3.12-slim

WORKDIR /app/jac

RUN pip install --no-cache-dir jaclang byllm requests

COPY . .

EXPOSE 8080

CMD ["jac", "start", "main.sv.jac", "--port", "8080", "--no_client"]
