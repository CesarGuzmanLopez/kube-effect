# kube-effect — todo lo comprueba `lint`.
QML_DIR := package
# /usr/bin/qmllint y /usr/bin/qmlformat son de qt5-declarative en esta distro:
# los de Qt 6 viven en /usr/lib/qt6/bin y son los que entienden QtQuick3D.
QT6_BIN ?= /usr/lib/qt6/bin
QMLLINT ?= $(QT6_BIN)/qmllint
QMLFORMAT ?= $(QT6_BIN)/qmlformat
QML_IMPORT ?= /usr/lib/qt6/qml
# Rules expected to fire on any KWin effect: context properties (effect,
# modelData, i18nd) and KWin types are not resolvable standalone, and Loader
# patterns / upstream naming trip the type checks. Anything else fails the gate.
QMLLINT_ALLOWED ?= unqualified missing-property import unused-imports incompatible-type id-shadows-member property-override
SONAR_URL := http://localhost:9000
SONAR_CONTAINER := kkube-sonar
SONAR_COMPOSE := docker-compose.sonar.yml

# Token local (secrets/ está prohibido para reales): env gana, si no .sonar-token (600, gitignored).
SONAR_TOKEN ?= $(shell cat .sonar-token 2>/dev/null)
export SONAR_TOKEN

space := $(subst ,, )

NATIVE_DIR := native
NATIVE := $(NATIVE_DIR)/build.sh
# Sources shipped inside the package so a store install can compile Plus on
# demand (ADR-018). native/ stays the source of truth; rsync keeps them equal.
NATIVE_PACKAGE_DIR := $(QML_DIR)/contents/native
# Anchored on the transfer root so build.sh is copied: only build trees are excluded.
NATIVE_SYNC_EXCLUDES := --exclude '/build/' --exclude '/build-system/' --exclude '*.o' --exclude 'CMakeFiles' --exclude '.cache'

.PHONY: lint lint-ci check quality sonar-scan sonar-up sonar-down deps format install nested \
	sync-package-native native native-install native-clean native-status

# Gate obligatorio en local: checks + análisis en el Sonar de localhost:9000.
lint: check sonar-scan

# Mismo gate sin Sonar: es lo que corre CI, donde no hay servidor.
lint-ci: check

# Comprobaciones sin servidor: qmllint, formato, esquema KCM, json, yaml.
# qmlformat no tiene modo "solo comprobar": formatea y git dice si cambió.
# check-schema.py cruza main.xml <-> config.ui <-> constants.js: defaults de
# enum válidos, mismo orden de choices (kwinrc guarda el índice), un widget por
# entry, clase de widget por tipo KConfigXT (Url->KUrlRequester, Color->
# KColorButton, Int->QSlider...), celdas del formulario sin solaparse (recorre
# tabs/scroll/grupos) y combos/spinboxes/sliders coherentes.
# check-ui.py construye el formulario con QUiLoader (lo que hace el KCM) para
# comprobar que cada widget se crea de verdad y su propiedad USER lleva el tipo
# del esquema. check-constants.py prueba los helpers de constants.js bajo el
# motor QML (modo de fondo, mapeo de imagen, ajuste, atenuación y valor Url
# real). Ambos se saltan (exit 0) si falta PySide6: CI no depende de ellos.
# check-scene-environment.py instancia en un motor QML real el SceneEnvironment
# del SkyBox con probeExposure (1.0 quieto, 0.4 girando con atenuación del 40 %)
# y falla si la propiedad no existe o el binding muere al animarla; su --selftest
# comprueba que una propiedad inexistente sí falla.
# check-video.py instancia HullVideo.qml (el único fichero que importa
# QtMultimedia) con un motor QML real y comprueba los dos caminos del Loader de
# ScreenView: módulo presente -> item y VideoOutput creados; módulo ausente y
# fuente rota -> Loader.Error sin llevarse la escena. También se salta (exit 0)
# si falta PySide6.
# check-features.py valida el catálogo features.json (campos obligatorios,
# status válido, ids únicos y dependencias conocidas); un JSON inválido rompe
# el gate. Su --selftest comprueba el propio validador (JSON inválido, id
# duplicado, status inválido, entrada no-objeto). Además, rsync en seco verifica
# que package/contents/native/ coincide con native/ (ADR-018). `make deps`
# sondea el sistema y avisa (sin fallar) de los módulos opcionales que falten.
check:
	@files=$$(find $(QML_DIR) -name '*.qml'); \
	if [ -n "$$files" ]; then \
		$(QMLLINT) -I $(QML_IMPORT) $$files > /tmp/kube-effect-qmllint.log 2>&1 || true; \
		bad=$$(grep -oE '\[[a-z-]+\]$$' /tmp/kube-effect-qmllint.log | tr -d '[]' | sort -u \
			| grep -vE "^($(subst $(space),|,$(QMLLINT_ALLOWED)))$$" || true); \
		if [ -n "$$bad" ]; then echo "qmllint: reglas nuevas sin revisar: $$bad"; cat /tmp/kube-effect-qmllint.log; exit 1; fi; \
		$(QMLFORMAT) -i $$files; \
		untracked=$$(git ls-files --others --exclude-standard -- $(QML_DIR) | grep -E '\.qml$$' || true); \
		if ! git diff --exit-code -- $(QML_DIR) || [ -n "$$untracked" ]; then \
			echo "qmlformat: el árbol no está formateado o hay QML nuevos sin trackear (git add):"; \
			git diff --stat -- $(QML_DIR); \
			if [ -n "$$untracked" ]; then echo "$$untracked"; fi; \
			exit 1; \
		fi; \
	fi
	@python3 scripts/check-schema.py
	@if [ -f $(QML_DIR)/contents/ui/config.ui ]; then python3 scripts/check-ui.py; else echo "check-ui: skipped (no config.ui, generic KCM)"; fi
	@if grep -q '^function ' $(QML_DIR)/contents/ui/constants.js 2>/dev/null; then python3 scripts/check-constants.py; else echo "check-constants: skipped (no helpers in constants.js)"; fi
	@python3 scripts/check-scene-environment.py
	@python3 scripts/check-scene-environment.py --selftest
	@python3 scripts/check-video.py
	@python3 scripts/check-features.py
	@python3 scripts/check-features.py --selftest
	@if [ ! -d $(NATIVE_PACKAGE_DIR) ]; then \
		echo "native: falta $(NATIVE_PACKAGE_DIR) (run: make sync-package-native)"; exit 1; \
	fi; \
	changes=$$(rsync -a --delete --dry-run --itemize-changes $(NATIVE_SYNC_EXCLUDES) \
		$(NATIVE_DIR)/ $(NATIVE_PACKAGE_DIR)/); \
	if [ -n "$$changes" ]; then \
		echo "native: $(NATIVE_PACKAGE_DIR) diverge de $(NATIVE_DIR):"; echo "$$changes"; \
		echo "run: make sync-package-native"; exit 1; \
	fi
	python3 -c "import json;json.load(open('$(QML_DIR)/metadata.json'))"
	python3 -c "import yaml;yaml.safe_load(open('.github/workflows/ci.yml'))"

# Sin token o sin servidor el gate falla con mensaje claro, no avisa y sigue.
sonar-scan:
	@if [ -z "$${SONAR_TOKEN:-}" ]; then \
		echo 'error: falta SONAR_TOKEN (env o .sonar-token con permisos 600)' >&2; exit 1; fi
	@curl -sf $(SONAR_URL)/api/system/status | grep -q '"status":"UP"' || \
		{ echo 'error: SonarQube no responde en localhost:9000; ejecuta make sonar-up' >&2; exit 1; }
	@python3 scripts/qmllint-sonar.py . build/qmllint-sonar.json
	@sonar-scanner -Dsonar.host.url=$(SONAR_URL) \
		-Dsonar.externalIssuesReportPaths=build/qmllint-sonar.json

# SonarQube local COMPARTIDO (contenedores kkube-sonar + kkube-sonar-db, una
# única instancia en localhost:9000). kube-effect es un proyecto MÁS en esa
# instancia; no crea una propia. Los contenedores se crean/gestionan desde
# kwin-effect-kkube (docker-compose.sonar.yml); aquí solo se arrancan/paran.
sonar-up:
	@if ! docker inspect kkube-sonar >/dev/null 2>&1; then \
		echo 'error: no existe la instancia compartida kkube-sonar; créala desde kwin-effect-kkube (docker-compose.sonar.yml)' >&2; exit 1; fi
	@docker start kkube-sonar-db kkube-sonar >/dev/null 2>&1 || true
	@echo 'esperando a SonarQube en $(SONAR_URL) (máx. 120 s)...'; \
	for i in $$(seq 1 60); do \
		if curl -sf $(SONAR_URL)/api/system/status | grep -q '"status":"UP"'; then \
			echo "sonar: $(SONAR_URL) UP"; exit 0; fi; \
		sleep 2; \
	done; \
	echo 'error: SonarQube no llegó a UP en 120 s; revisa: docker logs kkube-sonar' >&2; exit 1

# Para los contenedores compartidos (sin borrar volumen ni índice).
sonar-down:
	@docker stop kkube-sonar kkube-sonar-db >/dev/null 2>&1 || true

format:
	@files=$$(find $(QML_DIR) -name '*.qml'); if [ -n "$$files" ]; then $(QMLFORMAT) -i $$files; fi

# Optional quality extras. Each tool runs only if installed, so a clean
# machine still passes; `make deps` lists what is missing.
quality:
	@echo "quality: optional checks (skipped when the tool is absent)"
	@command -v shfmt >/dev/null && shfmt -d scripts/*.sh $(NATIVE) || echo "  shfmt: omitido"
	@for f in package/contents/config/main.xml package/contents/ui/config.ui; do \
		command -v xmllint >/dev/null && xmllint --noout "$$f" || echo "  xmllint: omitido"; \
	done
	@command -v jq >/dev/null && jq -e . package/metadata.json >/dev/null || echo "  jq: omitido"
	@command -v yamllint >/dev/null && yamllint -d relaxed .github/workflows/ci.yml || echo "  yamllint: omitido"
	@command -v reuse >/dev/null && reuse lint || echo "  reuse: omitido"
	@if command -v codespell >/dev/null; then codespell package docs scripts README.md; \
	elif command -v typos >/dev/null; then typos; else echo "  codespell/typos: omitido"; fi

# Re-check required/optional dependencies at any time.
deps:
	@./scripts/check-deps.sh

# Copy native/ (source of truth) into the package, without build trees. Safe to
# run repeatedly; `make install` does it first so the shipped sources never go
# stale (ADR-018).
sync-package-native:
	@mkdir -p $(NATIVE_PACKAGE_DIR)
	@rsync -a --delete $(NATIVE_SYNC_EXCLUDES) $(NATIVE_DIR)/ $(NATIVE_PACKAGE_DIR)/
	@echo "native: fuentes sincronizadas en $(NATIVE_PACKAGE_DIR)"

install: sync-package-native
	kpackagetool6 --type KWin/Effect --upgrade $(QML_DIR)/ || \
		kpackagetool6 --type KWin/Effect --install $(QML_DIR)/

# Optional Kube Effect Plus KCM (ADR-011/ADR-012/ADR-018). Never needed for the
# QML effect: its settings menu is the generic KCM and always works without
# compiling anything.
# `make native` installs into ~/.local (no root) and writes
# ~/.local/share/kube-effect/{native-stamp.json,prefix.sh}.
native:
	@./$(NATIVE)

# System-wide install: one sudo, and only for the install step. The stamp is
# written as the calling user so `make native-status` keeps working.
native-install:
	@./$(NATIVE) --system

native-clean:
	@rm -rf $(NATIVE_DIR)/build $(NATIVE_DIR)/build-system
	@echo "native: build trees removed"

# Exit 1 when the stamp is missing or the compiled Plasma/Qt no longer matches.
native-status:
	@./scripts/native-status.sh

nested:
	kwin_wayland --xwayland :2 &
