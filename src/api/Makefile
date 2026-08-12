include .env
export

.PHONY: run build sqlc migrate-up migrate-down migrate-create

run:
	go run ./cmd/api

build:
	go build -o bin/api ./cmd/api

sqlc:
	sqlc generate

# golang-migrate is not vendored; installs on first use.
migrate-up:
	go run -mod=mod github.com/golang-migrate/migrate/v4/cmd/migrate@latest -path db/migrations -database "$(DATABASE_URL)" up

migrate-down:
	go run -mod=mod github.com/golang-migrate/migrate/v4/cmd/migrate@latest -path db/migrations -database "$(DATABASE_URL)" down 1

# usage: make migrate-create name=add_something
migrate-create:
	go run -mod=mod github.com/golang-migrate/migrate/v4/cmd/migrate@latest create -ext sql -dir db/migrations -seq $(name)
