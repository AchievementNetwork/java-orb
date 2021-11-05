#!/bin/bash

set -o pipefail
set -u

TMP_FILES=()
trap 'if [ ${#TMP_FILES[@]} -ne 0 ]; then rm "${TMP_FILES[@]}"; fi' EXIT

if [ -z "$1" ]; then
	echo "Usage: create_circle_build <project>" 1>&2
	exit 1
fi

DATA_ARG=
if [ -n "${BRANCH}" ]; then
	DATA_ARG="--data '{\"branch\":\"${BRANCH}\"}'"
fi

OUTPUT_FILE=$(mktemp -t circleci)
TMP_FILES+=("${OUTPUT_FILE}")
STATUS_CODE=$(curl \
	--request POST \
	--silent \
	--output "${OUTPUT_FILE}" \
	--write-out "%{http_code}" \
	--header "Circle-Token: ${CIRCLECI_API_TOKEN}" \
	--header 'Accept: text/plain' \
	--header 'Content-Type: application/json' \
	${DATA_ARG} \
	"https://circleci.com/api/v2/project/gh/AchievementNetwork/$1/pipeline")

case "${STATUS_CODE}" in
	2*)
		WORKFLOW_NUMBER=$(jq -r ".number // \"\"" "${OUTPUT_FILE}")
		PIPELINE_ID=$(jq -r ".id // \"\"" "${OUTPUT_FILE}")
		if [ -n "${WORKFLOW_NUMBER}" ]  && [ -n "${PIPELINE_ID}" ]; then
			STATUS_CODE=$(curl \
				--request GET \
				--silent \
				--output "${OUTPUT_FILE}" \
				--write-out "%{http_code}" \
				--header "Circle-Token: ${CIRCLECI_API_TOKEN}" \
				--header 'Accept: text/plain' \
				--header 'Content-Type: application/json' \
				"https://circleci.com/api/v2/pipeline/$PIPELINE_ID/workflow")
			case "${STATUS_CODE}" in
				2*)
					WORKFLOW_ID=$(jq -r ".items[0].id // \"\"" "${OUTPUT_FILE}")
					if [ -n "${WORKFLOW_ID}" ]; then
						echo "https://app.circleci.com/pipelines/github/AchievementNetwork/$1/$WORKFLOW_NUMBER/workflows/$WORKFLOW_ID"
						exit 0
					fi
			esac
		fi
		echo "Success reported but no job details found - check https://app.circleci.com/pipelines/github/AchievementNetwork/$1"
		;;
	*)
		echo "Unable to create build for $1"
		exit 1
		;;
esac
