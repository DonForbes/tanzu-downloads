#!/usr/bin/env bash
# Copyright 2020 The TKG Contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

TANZU_BOM_DIR=${HOME}/.tanzu/tkg/bom
LEGACY_BOM_DIR=${HOME}/.tkg/bom
INSTALL_INSTRUCTIONS='See https://github.com/mikefarah/yq#install for installation instructions'

echodual() {
  echo "$@" 1>&2
  echo "#" "$@"
}

if [ -z "$1" ]; then
	echo "Please provide the image output directory"
	exit 1
else
	IMAGE_OUTPUT_DIRECTORY=$1	
fi

if [ -z "$IMAGE_OUTPUT_DIRECTORY" ]; then
  echo "IMAGE_OUTPUT_DIRECTORY variable is not defined" >&2
  exit 1
fi

if [[ -d "$TANZU_BOM_DIR" ]]; then
  BOM_DIR="${TANZU_BOM_DIR}"
elif [[ -d "$LEGACY_BOM_DIR" ]]; then
  BOM_DIR="${LEGACY_BOM_DIR}"
else
  echo "Tanzu Kubernetes Grid directories not found. Run CLI once to initialise." >&2
  exit 2
fi

if ! [ -x "$(command -v imgpkg)" ]; then
  echo 'Error: imgpkg is not installed.' >&2
  exit 3
fi

if ! [ -x "$(command -v yq)" ]; then
  echo 'Error: yq is not installed.' >&2
  echo "${INSTALL_INSTRUCTIONS}" >&2
  exit 3
fi

echo "set -euo pipefail"
echodual "Note that yq version must be equal to or above v4.5."

actualImageRepository=""
# Iterate through BoM file to create the complete Image name
# and then pull, retag and push image to custom registry.
for TKG_BOM_FILE in "$BOM_DIR"/*.yaml; do
  echodual "Processing BOM file ${TKG_BOM_FILE}"
  # Get actual image repository from BoM file
  actualImageRepository=$(yq e '.imageConfig.imageRepository' "$TKG_BOM_FILE")
  yq e '.. | select(has("images"))|.images[] | .imagePath + ":" + .tag ' "$TKG_BOM_FILE" |
    while read -r image; do
      actualImage=${actualImageRepository}/${image}
      echo "docker pull $actualImage"
      echo "docker save $actualImage --output ${IMAGE_OUTPUT_DIRECTORY}/$(echo ${actualImage} | tr '/' ',')"
      echo ""
    done
  echodual "Finished processing BOM file ${TKG_BOM_FILE}"
  echo ""
done

# Iterate through TKR BoM file to create the complete Image name
# and then pull, retag and push image to custom registry.
list=$(imgpkg  tag  list -i ${actualImageRepository}/tkr-bom)
for imageTag in ${list}; do
  if [[ ${imageTag} == v* ]]; then 
    TKR_BOM_FILE="tkr-bom-${imageTag//_/+}.yaml"
    echodual "Processing TKR BOM file ${TKR_BOM_FILE}"

    actualTKRImage=${actualImageRepository}/tkr-bom:${imageTag}
    echo ""
    echo "docker pull $actualTKRImage"
    echo "docker save $actualTKRImage --output ${IMAGE_OUTPUT_DIRECTORY}/$( echo ${actualTKRImage} | tr '/' ',')"
    imgpkg pull --image ${actualImageRepository}/tkr-bom:${imageTag} --output "tmp" > /dev/null 2>&1
    yq e '.. | select(has("images"))|.images[] | .imagePath + ":" + .tag ' "tmp/$TKR_BOM_FILE" |
    while read -r image; do
      actualImage=${actualImageRepository}/${image}
      echo "docker pull $actualImage"
      echo "docker save $actualImage --output ${IMAGE_OUTPUT_DIRECTORY}/$(echo ${actualImage} | tr '/' ',')"
      echo ""
    done
    rm -rf tmp
    echodual "Finished processing TKR BOM file ${TKR_BOM_FILE}"
    echo ""
  fi 
done

list=$(imgpkg  tag  list -i ${actualImageRepository}/tkr-compatibility)
for imageTag in ${list}; do
  if [[ ${imageTag} == v* ]]; then 
    echodual "Processing TKR compatibility image"
    actualImage=${actualImageRepository}/tkr-compatibility:${imageTag}
    echo ""
    echo "docker pull $actualImageRepository/tkr-compatibility:$imageTag"
    echo "docker save $actualImageRepository/tkr-compatibility:$imageTag --output ${IMAGE_OUTPUT_DIRECTORY}/$(echo ${actualImageRepository}.tkr-compatibility.$imageTag | tr '/' ',')"
    echo ""
    echodual "Finished processing TKR compatibility image"
  fi
done
