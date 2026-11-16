#!/usr/bin/env bash
# The launch arguments that run the app in one of its languages (tools/l10n.py LANGUAGES), with
# that language's region for dates, numbers and paper: ci/screenshots.sh's "+<language>" scenarios.
#   ci/language_args.sh de   →   -AppleLanguages (de) -AppleLocale de_DE
set -euo pipefail
case "$1" in
  de) region=de_DE ;; es) region=es_ES ;; fr) region=fr_FR ;; it) region=it_IT ;; ja) region=ja_JP ;;
  ko) region=ko_KR ;; nl) region=nl_NL ;; pt-BR) region=pt_BR ;; zh-Hans) region=zh_CN ;; zh-Hant) region=zh_TW ;;
  *) echo "ci/language_args.sh: no language $1" >&2; exit 1 ;;
esac
echo "-AppleLanguages ($1) -AppleLocale $region"
