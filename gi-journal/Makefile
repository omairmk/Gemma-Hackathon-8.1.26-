PYTHON := .venv/bin/python

.PHONY: setup model run test
setup:
	$(PYTHON) -m pip install -r requirements.txt

model:
	HF_HOME=$(CURDIR)/.hf_cache $(PYTHON) scripts/download_models.py

run:
	@echo "Runtime command will be enabled after PRECHECK records an eligible local model."

test:
	$(PYTHON) -m pytest -q
