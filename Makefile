.PHONY: setup dev start ngrok

setup:
	uv sync
	@if [ ! -f .env ]; then cp .env.example .env && echo ".env created — fill in your tokens"; fi

dev:
	uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload

start:
	uv run uvicorn main:app --host 0.0.0.0 --port 8000

ngrok:
	ngrok http 8000
