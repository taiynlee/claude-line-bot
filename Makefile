.PHONY: setup start stop dev ngrok

setup:
	uv sync
	@if [ ! -f .env ]; then cp .env.example .env && echo ".env created — fill in your tokens"; fi

start:
	bash start.sh

stop:
	bash stop.sh

dev:
	uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload

ngrok:
	ngrok http 8000
