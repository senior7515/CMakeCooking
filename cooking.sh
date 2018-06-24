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
# Depends on `build_dir`.
ingredients_dir=""
generator="Ninja"
list_only=""

usage() {
    echo "Usage: $0 [-r RECIPE] [-g GENERATOR (=${generator})] -d BUILD_DIR (=${build_dir}) -t BUILD_TYPE (=${build_type}) [-h]" 1>&2
}

while getopts "r:d:p:t:g:lh" arg; do
    case "${arg}" in
        r) recipe=${OPTARG} ;;
        d) build_dir=$(realpath "${OPTARG}") ;;
        p) ingredients_dir=$(realpath "${OPTARG}") ;;
        t) build_type=${OPTARG} ;;
        g) generator=${OPTARG} ;;
        l) list_only="1" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

shift $((OPTIND - 1))

cooking_dir="${build_dir}/_cooking"
cmake_dir="${source_dir}/cmake"
cache_file="${build_dir}/CMakeCache.txt"
ingredients_ready_file="${cooking_dir}/ready.txt"

if [ -z "${ingredients_dir}" ]; then
    ingredients_dir="${cooking_dir}/installed"
fi

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

  option (Cooking_LIST_ONLY
    "Available ingredients will be listed and nothing will be installed."
    OFF)

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

  add_custom_target (_cooking_ingredient_${name}_post_install
    DEPENDS ${Cooking_INGREDIENTS_DIR}/.cooking_ingredient_${name})

  add_dependencies (_cooking_ingredients _cooking_ingredient_${name}_post_install)

  if (Cooking_LIST_ONLY)
    add_custom_command (
      OUTPUT ${Cooking_INGREDIENTS_DIR}/.cooking_ingredient_${name}
      MAIN_DEPENDENCY ${Cooking_INGREDIENTS_DIR}/.cooking_stamp
      COMMAND ${CMAKE_COMMAND} -E touch ${Cooking_INGREDIENTS_DIR}/.cooking_ingredient_${name})
  else ()
    cmake_parse_arguments (
      _cooking_parsed_args
      ""
      ""
      "CMAKE_ARGS"
      ${_cooking_args})

    include (ExternalProject)
    set (_cooking_stow_dir ${_cooking_dir}/stow)
    string (REPLACE "<DISABLE>" "" _cooking_forwarded_args "${_cooking_parsed_args_UNPARSED_ARGUMENTS}")

    if (NOT (SOURCE_DIR IN_LIST _cooking_args))
      set (_cooking_source_dir SOURCE_DIR ${_cooking_ingredient_dir}/src)
    else ()
      set (_cooking_source_dir "")
    endif ()

    if (NOT ((BUILD_IN_SOURCE IN_LIST _cooking_args) OR (BINARY_DIR IN_LIST _cooking_args)))
      set (_cooking_binary_dir BINARY_DIR ${_cooking_ingredient_dir}/build)
    else ()
      set (_cooking_binary_dir "")
    endif ()

    if (NOT (UPDATE_COMMAND IN_LIST _cooking_args))
      set (_cooking_update_command UPDATE_COMMAND)
    else ()
      set (_cooking_update_command "")
    endif ()

    set (_cooking_extra_cmake_args
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>)

    if (NOT ("${ARGN}" MATCHES .*CMAKE_BUILD_TYPE.*))
      list (APPEND _cooking_extra_cmake_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
    endif ()

    if (NOT (CONFIGURE_COMMAND IN_LIST _cooking_args))
      set (_cooking_configure_command
        CONFIGURE_COMMAND
        ${CMAKE_COMMAND}
        ${_cooking_parsed_args_CMAKE_ARGS}
        ${_cooking_extra_cmake_args}
        <SOURCE_DIR>)
    else ()
      set (_cooking_configure_command "")
    endif ()

    if (NOT (BUILD_COMMAND IN_LIST _cooking_args))
      set (_cooking_build_command BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR>)
    else ()
      set (_cooking_build_command "")
    endif ()

    if (NOT (INSTALL_COMMAND IN_LIST _cooking_args))
      set (_cooking_install_command INSTALL_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target install)
    else ()
      set (_cooking_install_command "")
    endif ()

    ExternalProject_add (ingredient_${name}
      ${_cooking_source_dir}
      ${_cooking_binary_dir}
      ${_cooking_update_command} ""
      ${_cooking_configure_command}
      ${_cooking_build_command}
      ${_cooking_install_command}
      PREFIX ${_cooking_ingredient_dir}
      STAMP_DIR ${_cooking_ingredient_dir}/stamp
      INSTALL_DIR ${_cooking_stow_dir}/${name}
      STEP_TARGETS install
      CMAKE_ARGS ${_cooking_extra_cmake_args}
      "${_cooking_forwarded_args}")

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
  endif ()
endmacro ()
EOF

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

mkdir -p "${build_dir}"
cd "${build_dir}"

declare -a build_args

if [ "${generator}" == "Ninja" ]; then
    build_args+=(-v)
fi

if [ -n "${list_only}" ]; then
    cmake_cooking_args+=("-DCooking_LIST_ONLY=ON")
fi

cmake -DCMAKE_BUILD_TYPE="${build_type}" "${cmake_cooking_args[@]}" "${@}" -G "${generator}" "${source_dir}"
cmake --build . --target _cooking_ingredients_ready -- "${build_args[@]}"

#
# Report what we've done.
#

ingredients=($(find "${ingredients_dir}" -name '.cooking_ingredient_*' -printf '%f\n' | sed -r 's/\.cooking_ingredient_(.+)/\1/'))

if [ -z "${list_only}" ]; then
    printf "\nCooking: Installed the following ingredients:\n"
else
    printf "\nCooking: The following ingredients are necessary for this recipe:\n"
fi

for ingredient in "${ingredients[@]}"; do
    echo "  - ${ingredient}"
done

printf '\n'

if [ -n "${list_only}" ]; then
    exit 0
fi

#
# Configure the project, expecting all requirements satisfied.
#

cmake -DCMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY=ON .
