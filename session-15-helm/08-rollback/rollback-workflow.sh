#!/usr/bin/env bash
# Session 15 - Task 2: complete Helm rollback workflow
#   Install -> Upgrade -> Verify -> Upgrade again (broken) -> Verify -> Rollback -> Verify
#
# Uses the app-chart from 07-install-upgrade. Run from session-15-helm/08-rollback/
# against a running cluster (e.g. minikube):   bash rollback-workflow.sh
set -euo pipefail

RELEASE=rollback-demo
CHART=../07-install-upgrade/app-chart
DEPLOY=${RELEASE}-app

verify() {
  echo; echo "### $1"
  helm history "$RELEASE"
  kubectl get deploy "$DEPLOY" -o wide
  kubectl get pods -l app="$RELEASE"
}

# 1. Install (revision 1: nginx:1.24, 1 replica)
helm install "$RELEASE" "$CHART"
kubectl rollout status deploy/"$DEPLOY" --timeout=120s
verify "after install (rev 1)"

# 2. Upgrade (revision 2: nginx:1.25, 2 replicas) + verify
helm upgrade "$RELEASE" "$CHART" --set image.tag=1.25 --set replicaCount=2
kubectl rollout status deploy/"$DEPLOY" --timeout=120s
verify "after good upgrade (rev 2)"

# 3. Upgrade again with an image tag that does not exist (revision 3) + verify
helm upgrade "$RELEASE" "$CHART" --reuse-values --set image.tag=doesnotexist
if ! kubectl rollout status deploy/"$DEPLOY" --timeout=45s; then
  echo "rollout is stuck, as expected (ImagePullBackOff)"
fi
verify "after broken upgrade (rev 3)"

# 4. Rollback to the last good revision (creates revision 4) + verify
helm rollback "$RELEASE" 2
kubectl rollout status deploy/"$DEPLOY" --timeout=120s
verify "after rollback to 2 (rev 4)"
helm get values "$RELEASE"

# 5. Clean up (comment out to keep the release)
helm uninstall "$RELEASE"
