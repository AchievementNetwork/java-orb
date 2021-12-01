#!/bin/bash

set -o pipefail
set -u

TMP_FILES=()
trap 'if [ ${#TMP_FILES[@]} -ne 0 ]; then rm "${TMP_FILES[@]}"; fi' EXIT

if [ -z "${PROJECTS-}" ]; then
	echo "No projects specified" 1>&2
	exit 1
fi

if [ -z "${CIRCLECI_API_TOKEN-}" ]; then
	echo "No api token specified" 1>&2
	exit 1
fi

for project in ${PROJECTS-}; do
	OUTPUT_FILE=$(mktemp circleci.XXXXXX)
	TMP_FILES+=("${OUTPUT_FILE}")

	# Create the build
	CURL_CMD=(curl \
		--request POST \
		--silent \
		--output "${OUTPUT_FILE}" \
		--write-out "%{http_code}" \
		--header "Circle-Token: ${CIRCLECI_API_TOKEN}" \
		--header 'Accept: text/plain' \
		--header 'Content-Type: application/json')
	if [ -n "${BRANCH-}" ]; then
		CURL_CMD+=(--data "{\"branch\":\"${BRANCH}\"}")
	fi
	CURL_CMD+=("https://circleci.com/api/v2/project/gh/AchievementNetwork/${project}/pipeline")
	STATUS_CODE=$("${CURL_CMD[@]}")

	case "${STATUS_CODE}" in
		2*)
			# If the build request was successful, look up the workflow that was created

			# First sleep to allow CircleCI to reach consistency
			sleep 5

			# Now look up the workflow
			WORKFLOW_NUMBER=$(jq -r ".number // \"\"" "${OUTPUT_FILE}")
			PIPELINE_ID=$(jq -r ".id // \"\"" "${OUTPUT_FILE}")
			WORKFLOW_ID=
			if [ -n "${WORKFLOW_NUMBER}" ] && [ -n "${PIPELINE_ID}" ]; then
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
							echo "https://app.circleci.com/pipelines/github/AchievementNetwork/${project}/$WORKFLOW_NUMBER/workflows/$WORKFLOW_ID"
						fi
				esac
			fi

			if [ -z "${WORKFLOW_ID}" ]; then
				echo "Success reported but no job details found - check https://app.circleci.com/pipelines/github/AchievementNetwork/${project}"
			fi
			;;
		*)
			echo "Unable to create build for ${project}"
			exit 1
			;;
	esac
done
