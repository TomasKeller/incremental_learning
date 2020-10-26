.PHONY: clean data lint requirements setup

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BUCKET = [OPTIONAL] your-bucket-for-syncing-data (do not include 's3://')
PROFILE = default
PROJECT_NAME = incremental_learning

ARGS := $(filter-out pkg-install,$(MAKECMDGOALS))

.DEFAULT: ;: do nothing

SHELL = /bin/bash

# Exit if conda is not installed !!
ifeq (,$(shell which conda))
$(error conda is not installed! Install conda from https://docs.conda.io/projects/conda/en/latest/user-guide/install/ !)
endif

CONDA_ROOT := $(shell sh -c "conda info -s | grep CONDA_ROOT | cut -d' ' -f2")

#################################################################################
# COMMANDS                                                                      #
#################################################################################

## Run jupyter lab
run:
	source $(CONDA_ROOT)/bin/activate $(PROJECT_NAME) && jupyter lab

## Setup the whole project
setup: setup-git environment setup-dsns run

## Setup git repository, add submodules and install DSNs
setup-git:
ifeq (,$(wildcard .git))
	@echo 'Initializing git repository and adding initial commit!'
	git init .
	git add .
	git commit -m 'Initial commit'
	git submodule init
	git submodule add git@ssh.dev.azure.com:v3/c-finance/Analytics/install_dsns external/install_dsns
	git commit -am 'Adding submodules'
	@echo 'git repo setup finalized!'
endif

setup-dsns:
	@echo 'Installing DSNs to your system and testing connection!'
	cd external/install_dsns && \
	source $(CONDA_ROOT)/bin/activate $(PROJECT_NAME) && \
	sudo bash install_dsn.sh dsn.conf

## Update conda environment or create it and then freeze the dependencies in environment.yml.lock:
environment: environment.yml.lock

environment.yml.lock: environment.yml
	@echo "CONDA installation found at $(CONDA_ROOT)"
	test -d "$(CONDA_ROOT)/envs/$(PROJECT_NAME)" && { \
		echo "$(PROJECT_NAME) env was found! Updating it ..."; \
		PIP_SRC=$(CONDA_ROOT)/envs/$(PROJECT_NAME)/src conda env update -f environment.yml --prune; \
		echo 'conda env update finalized!'; \
	} || { \
		echo '$(PROJECT_NAME) env was not found! Setting it up ...'; \
		PIP_SRC=$(CONDA_ROOT)/envs/$(PROJECT_NAME)/src conda env create -f environment.yml; \
		echo 'conda env create finalized!'; \
	}

	@echo "Freezing current conda environment..."
	{ \
		source $(CONDA_ROOT)/bin/activate $(PROJECT_NAME) && \
		conda env export -n $(PROJECT_NAME) | sed -E '/(prefix)|(^$$)/d'; \
		echo '  - pip:'; \
		pip freeze | grep -E "\-e \w+" | sed -E 's/-e (.*)/    - "--editable \1"/g'; \
	} > environment.yml.lock
	@echo "Created environment.yml.lock file with frozen conda env"

	## @echo "Installing widget extensions..."
	## jupyter nbextension enable --py widgetsnbextension
	## jupyter labextension install @jupyter-widgets/jupyterlab-manager --no-build
	## @echo "Finished installing widget extensions!"

## Install new python package
pkg-install: add-pkg environment
add-pkg:
	test -n $(ARGS) && { \
		conda search $(ARGS) -q | tail -n+3 | grep -oE '^\w+'; \
	} && { \
	echo "  # automatically added by __make__ on $$(date +%d-%m-%Y" "%H:%M:%S)"; \
	echo '  - $(ARGS)'; \
	} >> environment.yml

## Make Dataset
data: environment
	python3 src/data/make_dataset.py data/raw data/processed

## Delete all compiled Python files
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete

## Lint using flake8
lint:
	flake8 src

## Test python environment is setup correctly
test_environment:
	python3 test_environment.py

#################################################################################
# PROJECT RULES                                                                 #
#################################################################################



#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
