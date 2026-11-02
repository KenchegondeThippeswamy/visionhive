up:
	docker compose -f docker/docker-compose.yml up -d --build
down:
	docker compose -f docker/docker-compose.yml down -v
logs:
	docker compose -f docker/docker-compose.yml logs -f --tail=50
ps:
	docker compose -f docker/docker-compose.yml ps
test:
	./scripts/smoke-test.sh
scale-workers:
	docker compose -f docker/docker-compose.yml up -d --scale ingest-worker=3
