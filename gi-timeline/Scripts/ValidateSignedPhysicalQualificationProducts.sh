#!/bin/zsh
set -euo pipefail

readonly script_directory="${0:A:h}"
exec /usr/bin/python3 "${script_directory}/ValidateSignedPhysicalQualificationProducts.py" "$@"
