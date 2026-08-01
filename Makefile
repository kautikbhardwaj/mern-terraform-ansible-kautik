SHELL := /bin/bash

.PHONY: init plan apply inventory deps configure deploy destroy all

init:
	terraform -chdir=terraform init

plan:
	terraform -chdir=terraform plan

apply:
	terraform -chdir=terraform apply -auto-approve

inventory:
	./generate-inventory.sh

deps:
	ansible-galaxy collection install -r ansible/requirements.yml

configure:
	cd ansible && ansible-playbook site.yml

deploy:
	cd ansible && ansible-playbook deploy.yml

destroy:
	terraform -chdir=terraform destroy -auto-approve

all: init apply inventory deps configure
