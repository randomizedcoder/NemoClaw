# Security scan for the NemoClaw OCI container image.
# Runs trivy (vulnerability scan) and dockle (best-practice lint) against the
# built container tarball. No Docker daemon required — scans the tarball directly.
#
# Usage: nix run .#container-scan
{
  writeShellApplication,
  coreutils,
  trivy,
  dockle,
  container,
}:

writeShellApplication {
  name = "nemoclaw-container-scan";

  runtimeInputs = [
    coreutils
    trivy
    dockle
  ];

  text = ''
    set -euo pipefail

    IMAGE_TARBALL="${container}"
    EXIT_CODE=0

    echo "=== NemoClaw Container Security Scan ==="
    echo "Image: $IMAGE_TARBALL"
    echo ""

    # ── Trivy: vulnerability scan ───────────────────────────────
    echo "--- trivy (vulnerability scan) ---"
    echo ""
    # --ignore-unfixed: only show vulns with available fixes
    # --show-suppressed=false: hide suppressed findings
    # exit-code 0: don't fail the scan (informational), but report findings
    trivy image \
        --input "$IMAGE_TARBALL" \
        --severity HIGH,CRITICAL \
        --scanners vuln \
        --ignore-unfixed \
        --exit-code 0 \
        --quiet \
        --format table \
        --skip-db-update=false \
      2>&1 | {
        # Filter the massive summary table — only show rows with actual findings
        in_summary=false
        while IFS= read -r line; do
          if [[ "$line" == *"Report Summary"* ]]; then
            in_summary=true
            continue
          fi
          # Skip summary table lines (they start with │ or ├ or └ or ┌)
          if $in_summary; then
            continue
          fi
          echo "$line"
        done
      }
    echo ""
    echo "trivy: scan complete"

    echo ""

    # ── Dockle: container best-practice lint ─────────────────────
    echo "--- dockle (best-practice lint) ---"
    echo ""
    # Accept CIS-DI-0010 + .env: upstream openclaw dependency ships a .env file
    # that we cannot remove. All other findings are shown transparently.
    # --exit-code 1: fail on WARN or higher (INFO findings are acceptable)
    if ! dockle \
        --input "$IMAGE_TARBALL" \
        --exit-code 1 \
        --accept-key "CIS-DI-0010" \
        --accept-file ".env" ; then
      echo ""
      echo "dockle: WARN or FATAL findings detected"
      EXIT_CODE=1
    fi
    echo ""
    echo "dockle: scan complete"

    echo ""
    echo "=== Scan Complete ==="
    exit "$EXIT_CODE"
  '';
}
