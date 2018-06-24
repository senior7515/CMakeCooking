#!/bin/bash

# MIT License
#
# Copyright (c) 2018 Jesse Haber-Kucharsky
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#
# This is cmake-cooking v0.4.0
#

set -e

source_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

recipe=""
build_dir="${source_dir}/build"
build_type="Debug"
generator="Ninja"

usage() {
    echo "Usage: $0 [-r RECIPE] [-g GENERATOR (=${generator})] -d BUILD_DIR (=${build_dir}) -t BUILD_TYPE (=${build_type}) [-h]" 1>&2
}

while getopts "r:g:d:t:h" arg; do
    case "${arg}" in
        r) recipe=${OPTARG} ;;
        g) generator=${OPTARG} ;;
        d) build_dir=${OPTARG} ;;
        t) build_type=${OPTARG} ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

shift $((OPTIND - 1))

cooking_dir="${build_dir}/_cooking"
cmake_dir="${source_dir}/cmake"
cache_file="${build_dir}/CMakeCache.txt"
ingredients_dir="${cooking_dir}/installed"
ingredients_ready_file="${cooking_dir}/ready.txt"

mkdir -p "${cmake_dir}"

cat <<'EOF' > "${cmake_dir}/Cooking.cmake"
# This file was generated by cmake-cooking v0.4.0.
# cmake-cooking is copyright 2018 by Jesse Haber-Kucharsky and
# available under the terms of the MIT license.

macro (project name)
  set (_cooking_dir ${CMAKE_CURRENT_BINARY_DIR}/_cooking)

  if (CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    set (_cooking_root ON)
  else ()
    set (_cooking_root OFF)
  endif ()

  set (Cooking_INGREDIENTS_DIR
    ${_cooking_dir}/installed
    CACHE
    PATH
    "Directory where ingredients will be installed.")

  set (Cooking_RECIPE "" CACHE STRING "Configure ${name}'s dependencies according to the named recipe.")

  if (_cooking_root)
    _project (${name} ${ARGN})

    if (NOT ("${Cooking_RECIPE}" STREQUAL ""))
      add_custom_target (_cooking_ingredients)

      add_custom_command (
        OUTPUT ${_cooking_dir}/ready.txt
        DEPENDS _cooking_ingredients
        COMMAND ${CMAKE_COMMAND} -E touch ${_cooking_dir}/ready.txt)

      add_custom_target (_cooking_ingredients_ready
        DEPENDS ${_cooking_dir}/ready.txt)

      list (APPEND CMAKE_PREFIX_PATH ${Cooking_INGREDIENTS_DIR})
      include ("recipe/${Cooking_RECIPE}.cmake")

      if (NOT EXISTS ${_cooking_dir}/ready.txt)
        return ()
      endif ()
    endif ()
  endif ()
endmacro ()

macro (cooking_ingredient name)
  set (_cooking_args "${ARGN}")
  set (_cooking_ingredient_dir ${_cooking_dir}/ingredient/${name})

  if (SOURCE_DIR IN_LIST _cooking_args)
    set (_cooking_source_dir "")
  else ()
    set (_cooking_source_dir SOURCE_DIR ${_cooking_ingredient_dir}/src)
  endif ()

  if ("${ARGN}" MATCHES .*CMAKE_BUILD_TYPE.*)
    set (_cooking_build_type "")
  else ()
    set (_cooking_build_type CMAKE_ARGS -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
  endif ()

  add_custom_target (_cooking_ingredient_${name}_post_install
    DEPENDS ${Cooking_INGREDIENTS_DIR}/.cooking_ingredient_${name})

  add_dependencies (_cooking_ingredients _cooking_ingredient_${name}_post_install)

  include (ExternalProject)
  set (_cooking_stow_dir ${_cooking_dir}/stow)

  ExternalProject_add (ingredient_${name}
    ${_cooking_source_dir}
    ${_cooking_build_type}
    PREFIX ${_cooking_ingredient_dir}
    STAMP_DIR ${_cooking_ingredient_dir}/stamp
    BINARY_DIR ${_cooking_ingredient_dir}/build
    INSTALL_DIR ${_cooking_stow_dir}/${name}
    CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    STEP_TARGETS install
    "${ARGN}")

  add_custom_command (
    OUTPUT ${Cooking_INGREDIENTS_DIR}/.cooking_ingredient_${name}
    MAIN_DEPENDENCY ${Cooking_INGREDIENTS_DIR}/.cooking_stamp
    DEPENDS ingredient_${name}-install
    COMMAND
      flock
      --wait 30
      ${Cooking_INGREDIENTS_DIR}/.cooking_stow.lock
      stow
      -t ${Cooking_INGREDIENTS_DIR}
      -d ${_cooking_stow_dir}
      ${name}
    COMMAND ${CMAKE_COMMAND} -E touch ${Cooking_INGREDIENTS_DIR}/.cooking_ingredient_${name})

  add_dependencies (_cooking_ingredients ingredient_${name})
endmacro ()
EOF

mkdir -p "${build_dir}"
cd "${build_dir}"

cmake_cooking_args=(
    "-DCooking_INGREDIENTS_DIR=${ingredients_dir}"
    "-DCooking_RECIPE=${recipe}"
)

#
# Clean-up from a previous run.
#

if [ -e "${ingredients_ready_file}" ]; then
    rm "${ingredients_ready_file}"
fi

if [ -e "${cache_file}" ]; then
    rm "${cache_file}"
fi

if [ -d "${ingredients_dir}" ]; then
    rm -r --preserve-root "${ingredients_dir}"
fi

mkdir -p "${ingredients_dir}"
touch "${ingredients_dir}/.cooking_stamp"

#
# Validate recipe.
#

if [ -n "${recipe}" ]; then
    recipe_file="${source_dir}/recipe/${recipe}.cmake"

    if [ ! -f "${recipe_file}" ]; then
        echo "Cooking: The '${recipe}' recipe does not exist!" && exit 1
    fi
fi

#
# Configure and build ingredients.
#

declare -a build_args

if [ "${generator}" == "Ninja" ]; then
    build_args+=(-v)
fi

cmake -DCMAKE_BUILD_TYPE="${build_type}" "${cmake_cooking_args[@]}" "${@}" -G "${generator}" "${source_dir}"
cmake --build . --target _cooking_ingredients_ready -- "${build_args[@]}"

#
# Configure the project, expecting all requirements satisfied.
#

cmake -DCMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY=ON .
