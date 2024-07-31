#!/usr/bin/env bash

set -e

COMPOSE_VERSION=v2.29.1
DOCKER_VERSION=27.1.1
DOCKER_MIRROR=
lines=$(awk 'END {print NR+1}' docker.run)


function parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --arch)
        if [[ "$2" == "x86_64" || "$2" == "aarch64" ]]; then
          ARCH="$2"
        else
          _error "标签 --arch 的值只能是 x86_64 或者 aarch64."
          exit 1
        fi
        shift
        ;;
      --mirror)
        DOCKER_MIRROR="$2"
        shift
        ;;
      *)
        _error "不支持的标签: $1"
        exit 1
        ;;
    esac
    shift
  done
}

function _log() {
    local log_level_int=$1
    local log_level_str=$2
    local message=${@:3}

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    local color_reset='\033[0m'
    local color_red='\033[0;31m'
    local color_white='\033[1;37m'

    local color=""
    if [ "$log_level_str" == "ERROR" ]; then
        color=$color_red
    elif [ "$log_level_str" == "INFO" ]; then
        color=$color_white
    fi

    local log_message="[$timestamp] [$log_level_str] - $message"
    echo -e "${color}${log_message}${color_reset}" | tee -a "${PWD}/${0}.log"
}

function _error() {
    _log 1 "ERROR" "$@"
}

function _info() {
    _log 0 "INFO" "$@"
}


function is_exist() {
  local missing_files=()

  for file in "$@"; do
    if [[ ! -e "$file" ]]; then
      missing_files+=("$file")
    fi
  done

  if [[ ${#missing_files[@]} -ne 0 ]]; then
    _error "以下文件或文件夹不存在："
    for missing_file in "${missing_files[@]}"; do
      _error "$missing_file"
    done
    exit 1
  fi
}

function download_docker() {
  _info "开始下载 docker"

  local TYPE=static
  local CHANNEL=stable

  if [[ -z "$DOCKER_VERSION" ]]; then
    _error "请设置 DOCKER_VERSION"
    return 1
  fi

  download_url="${DOCKER_MIRROR}/$OS/$TYPE/$CHANNEL/${ARCH}/docker-${DOCKER_VERSION}.tgz"
  _info "下载地址：$download_url"

  wget -c -O docker.tgz "$download_url"

  _info "docker 下载完成"
}

function download_docker_compose() {
  _info "开始下载 docker-compose"

  url="$COMPOSE_MIRROR/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$OS-$ARCH"

  wget -c -O docker-compose "$url"

  chmod +x docker-compose

  _info "docker-compose 下载完成"
}

function repack_docker() {

  _info "开始打包所有资源"

  is_exist docker.tgz docker-compose

  tar -vxf docker.tgz

  mv docker-compose docker/

  tar -cf - docker/ | xz -9 -T 0 --block-size=64MiB --memlimit-compress=12GiB -c - > docker.tar.xz

  tarball_md5=$(md5sum docker.tar.xz|awk '{print $1}')
  sed -i "s/^tarball_md5=[a-f0-9]\{32\}$/tarball_md5=${tarball_md5}/" docker.run
  sed -i "s/^lines=[0-9]\+$/lines=${lines}/" docker.run
  cat docker.run > ${PACKAGE_NAME}
  cat docker.tar.xz >> ${PACKAGE_NAME}

  _info "打包完成"
}

function test_repack() {
  _info "开始校验打包结果"

  tail -n+${lines} ${PACKAGE_NAME} > docker.test
  md5=$(md5sum docker.test | cut -d' ' -f1)
  if [[ "$md5" != "$tarball_md5" ]]; then
    _error "md5 校验失败"
    exit 1
  fi
  _info "校验完成"
}

function clean() {
  _info "开始清理临时文件"

  items=("docker.tgz" "docker.tar.xz" "docker.test" "docker")

  for item in "${items[@]}"; do
    if [[ -d "$item" ]]; then
      rm -rf "$item"
    elif [[ -f "$item" ]]; then
      rm -f "$item"
    else
      _info "$item 文件不存在"
    fi
  done

  _info "清理完成"
}


parse_args "$@"

# 设置默认值
DOCKER_MIRROR="${DOCKER_MIRROR:-https://download.docker.com}"
OS="${OS:-linux}"
ARCH="${ARCH:-x86_64}"
COMPOSE_MIRROR="${COMPOSE_MIRROR:-https://github.com}"
PACKAGE_NAME=docker_${DOCKER_VERSION}_${ARCH}.install

_info "开始生成 docker 安装包"

download_docker
download_docker_compose
repack_docker
test_repack
clean

_info "docker 安装包已生成，文件名：${PACKAGE_NAME}"
