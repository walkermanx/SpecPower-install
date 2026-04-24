#!/usr/bin/env bash
# SpecPower 安装脚本
# 自动判断当前是否为 skill 目录，如果不是则克隆仓库后安装
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
  echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
  echo -e "${RED}[错误]${NC} $1"
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURRENT_DIR="$(pwd)"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 交互式菜单函数
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 读取按键 (处理方向键转义序列)
# 结果写入 KEY_RESULT: up / down / enter / space / a / q / 其他字符
_read_key() {
  local key
  # 读取单个字符（从 /dev/tty 读取以支持管道执行）
  IFS= read -rsn1 key </dev/tty 2>/dev/null || {
    # 如果 read 失败，可能是遇到了回车键
    KEY_RESULT=enter
    return
  }

  # 处理读取到的字符
  case "$key" in
    '')  KEY_RESULT=enter ;;  # 空字符串通常表示回车
    $'\e')
      local seq
      IFS= read -rsn2 seq </dev/tty 2>/dev/null || true
      case "$seq" in
        '[A') KEY_RESULT=up ;;
        '[B') KEY_RESULT=down ;;
        *)    KEY_RESULT=other ;;
      esac
      ;;
    ' ')   KEY_RESULT=space ;;
    a|A)   KEY_RESULT=a ;;
    q|Q)   KEY_RESULT=q ;;
    y|Y)   KEY_RESULT=y ;;
    n|N)   KEY_RESULT=n ;;
    *)     KEY_RESULT=other ;;
  esac
}

# 多选菜单: 上/下键移动, 空格切换选中, 回车确认, a 全选/取消全选
# 用法: menu_multi "提示语" item1 item2 ...
# 结果: MENU_RESULTS = 选中索引数组 (1-based), MENU_RESULT = 0 表示放弃
menu_multi() {
  local prompt="$1"; shift
  local -a items=("$@")
  local count=${#items[@]}
  local cur=1
  local total_lines=$(( count + 1 ))
  local -a selected=()

  printf '\e[?25l'
  trap 'printf "\e[?25h"' INT TERM

  printf '%b\n' "$prompt  \e[2m(↑↓:移动  空格:切换选中  a:全选  回车:确认)\e[0m"
  while true; do
    for i in $(seq 1 $count); do
      local mark=" "
      # 检查是否选中
      if [[ ${#selected[@]} -gt 0 ]]; then
        for j in "${selected[@]}"; do
          if [[ "$j" == "$i" ]]; then
            mark="✓"
            break
          fi
        done
      fi
      if (( i == cur )); then
        printf '\e[36m  ❯ [%s] %s\e[0m\n' "$mark" "${items[$((i-1))]}"
      else
        printf '    [%s] %s\n' "$mark" "${items[$((i-1))]}"
      fi
    done
    if (( cur == 0 )); then
      printf '\e[36m  ❯ 放弃\e[0m\n'
    else
      printf '    放弃\n'
    fi

    _read_key
    case "$KEY_RESULT" in
      up)
        if (( cur == 0 )); then
          cur=$count
        elif (( cur > 1 )); then
          (( cur-- )) || true
        fi
        ;;
      down)
        if (( cur > 0 && cur < count )); then
          (( cur++ )) || true
        elif (( cur == count )); then
          cur=0
        fi
        ;;
      space)
        if (( cur >= 1 )); then
          # 检查是否已选中
          local found=0
          local index=0
          if [[ ${#selected[@]} -gt 0 ]]; then
            for j in "${selected[@]}"; do
              if [[ "$j" == "$cur" ]]; then
                found=1
                break
              fi
              ((index++))
            done
          fi
          if (( found )); then
            # 取消选中
            selected=("${selected[@]:0:$index}" "${selected[@]:$((index+1))}")
          else
            # 选中
            selected+=("$cur")
          fi
        fi
        ;;
      a)
        if (( ${#selected[@]} == count )); then
          selected=()
        else
          selected=()
          for i in $(seq 1 $count); do selected+=("$i"); done
        fi
        ;;
      enter)
        if (( cur == 0 )); then
          MENU_RESULTS=()
          MENU_RESULT=0
          break
        fi
        if [[ ${#selected[@]} -eq 0 ]]; then
          selected+=("$cur")
        fi
        MENU_RESULTS=("${selected[@]}")
        MENU_RESULT=1
        break
        ;;
      q)
        MENU_RESULTS=()
        MENU_RESULT=0
        break
        ;;
    esac
    printf "\e[${total_lines}A"
  done

  printf '\e[?25h'
}

# 确认菜单: 上/下键选择 确认/放弃
# 用法: menu_confirm "提示语"
# 结果: MENU_RESULT = 1(确认) 或 0(放弃)
menu_confirm() {
  local prompt="$1"
  local cur=1

  printf '\e[?25l'
  trap 'printf "\e[?25h"' INT TERM

  [[ -n "$prompt" ]] && echo "$prompt"
  while true; do
    if (( cur == 1 )); then
      printf '\e[32m  ❯ 确认执行\e[0m\n'
      printf '    放弃\n'
    else
      printf '    确认执行\n'
      printf '\e[31m  ❯ 放弃\e[0m\n'
    fi

    _read_key
    case "$KEY_RESULT" in
      up|down) (( cur = cur == 1 ? 0 : 1 )) || true ;;
      enter) break ;;
      y) cur=1; break ;;
      q|n) cur=0; break ;;
    esac
    printf "\e[2A"
  done

  printf '\e[?25h'
  MENU_RESULT=$cur
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 1: 判断当前目录是否存在 SKILL.md 文件
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_info "检查当前目录: $CURRENT_DIR"

if [[ -f "$CURRENT_DIR/SKILL.md" ]]; then
  # ─── 情况 1: 当前目录存在 SKILL.md ───
  print_success "检测到当前目录已包含 SKILL.md 文件"

  # 获取 Skill 名称
  SKILL_NAME="$(basename "$CURRENT_DIR")"
  SOURCE_DIR="$CURRENT_DIR"

  print_info "Skill 目录: $SOURCE_DIR ($SKILL_NAME)"
  echo ""

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 查找目标目录（项目级 & 用户级）
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  PROJECT_TARGETS=()
  search_dir="$SOURCE_DIR"

  # 向上搜索 4 层，查找项目级配置目录
  for level in 0 1 2 3; do
    for config_dir in ".claude" ".micode" ".cursor" ".opencode"; do
      candidate="$search_dir/$config_dir"
      if [[ -d "$candidate" ]]; then
        PROJECT_TARGETS+=("$candidate/skills")
      fi
    done
    parent="$(dirname "$search_dir")"
    [[ "$parent" == "$search_dir" ]] && break
    search_dir="$parent"
  done
  # 去重（安全访问数组）
  if [[ ${#PROJECT_TARGETS[@]} -gt 0 ]]; then
    PROJECT_TARGETS=($(printf "%s\n" "${PROJECT_TARGETS[@]}" | sort -u))
  fi

  # 查找用户级配置目录
  USER_TARGETS=()
  for config_dir in ".claude" ".micode" ".cursor"; do
    if [[ -d "$HOME/$config_dir" ]]; then
      USER_TARGETS+=("$HOME/$config_dir/skills")
    fi
  done
  # OpenCode 用户级目录特殊处理: ~/.config/opencode
  if [[ -d "$HOME/.config/opencode" ]]; then
    USER_TARGETS+=("$HOME/.config/opencode/skills")
  fi
  # 去重（安全访问数组）
  if [[ ${#USER_TARGETS[@]} -gt 0 ]]; then
    USER_TARGETS=($(printf "%s\n" "${USER_TARGETS[@]}" | sort -u))
  fi

  # 检查是否找到目标目录
  if [[ ${#PROJECT_TARGETS[@]} -eq 0 && ${#USER_TARGETS[@]} -eq 0 ]]; then
    print_error "未找到任何配置目录 (.claude、.micode、.cursor 或 .opencode)"
    print_info "请确保至少存在以下目录之一："
    print_info "  - 项目级: 当前目录向上 3 层中的 .claude/skills、.micode/skills 等"
    print_info "  - 用户级: ~/.claude/skills、~/.micode/skills 等"
    exit 1
  fi

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 构建目标列表并显示选择菜单
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ALL_TARGETS=()
  TARGET_LABELS=()

  # 构建项目级目标标签
  if [[ ${#PROJECT_TARGETS[@]} -gt 0 ]]; then
    for target in "${PROJECT_TARGETS[@]}"; do
      ALL_TARGETS+=("$target")
      if [[ -d "$target/$SKILL_NAME" ]]; then
        TARGET_LABELS+=("[项目级] $target  (已存在 $SKILL_NAME/)")
      elif [[ -d "$target" ]]; then
        TARGET_LABELS+=("[项目级] $target  (已有 skills/)")
      else
        TARGET_LABELS+=("[项目级] $target  (将自动创建 skills/)")
      fi
    done
  fi

  # 构建用户级目标标签
  if [[ ${#USER_TARGETS[@]} -gt 0 ]]; then
    for target in "${USER_TARGETS[@]}"; do
      ALL_TARGETS+=("$target")
      if [[ -d "$target/$SKILL_NAME" ]]; then
        TARGET_LABELS+=("[用户级] $target  (已存在 $SKILL_NAME/)")
      elif [[ -d "$target" ]]; then
        TARGET_LABELS+=("[用户级] $target  (已有 skills/)")
      else
        TARGET_LABELS+=("[用户级] $target  (将自动创建 skills/)")
      fi
    done
  fi

  # 使用交互式多选菜单
  echo ""
  menu_multi "🔍 请选择要安装到的目标目录:" "${TARGET_LABELS[@]}"

  if [[ $MENU_RESULT -eq 0 || ${#MENU_RESULTS[@]} -eq 0 ]]; then
    print_warning "已取消安装"
    exit 0
  fi

  # 构建选中的目录列表
  SELECTED_DIRS=()
  for idx in "${MENU_RESULTS[@]}"; do
    SELECTED_DIRS+=("${ALL_TARGETS[$((idx-1))]}")
  done

  # 去重
  if [[ ${#SELECTED_DIRS[@]} -gt 0 ]]; then
    SELECTED_DIRS=($(printf "%s\n" "${SELECTED_DIRS[@]}" | sort -u))
  fi

  if [[ ${#SELECTED_DIRS[@]} -eq 0 ]]; then
    print_warning "未选择任何有效目标，已取消安装"
    exit 0
  fi

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 确认操作
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  echo ""
  print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_info "即将执行以下复制操作:"
  echo ""

  for dir in "${SELECTED_DIRS[@]}"; do
    dst="$dir/$SKILL_NAME"
    if [[ -d "$dst" ]]; then
      print_warning "  [覆盖] $dst (已存在)"
    else
      echo "  [新建] $dst"
    fi
  done

  print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # 使用交互式确认菜单
  menu_confirm ""

  if [[ $MENU_RESULT -eq 0 ]]; then
    print_warning "已取消安装"
    exit 0
  fi

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 执行复制（最小化安装）
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # 定义必需的文件和目录
  REQUIRED_ITEMS=(
    "SKILL.md"
    "agents"
    "references"
  )

  created=0
  updated=0

  for dir in "${SELECTED_DIRS[@]}"; do
    dst="$dir/$SKILL_NAME"

    # 确保父目录存在
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir"
      print_info "创建目录: $dir"
    fi

    # 如果目标已存在，先删除
    if [[ -d "$dst" ]]; then
      print_info "删除现有目录: $dst"
      rm -rf "$dst"
      ((updated++))
    else
      ((created++))
    fi

    # 创建目标目录
    mkdir -p "$dst"

    # 复制必需的文件和目录
    for item in "${REQUIRED_ITEMS[@]}"; do
      src="$SOURCE_DIR/$item"
      if [[ -e "$src" ]]; then
        cp -r "$src" "$dst/"
        print_info "  ✓ 已复制: $item"
      else
        print_warning "  ⚠ 未找到: $item"
      fi
    done

    print_success "已安装到: $dst"
  done

  echo ""
  print_success "安装完成! 新建 $created 个，更新 $updated 个"
  print_info "已安装文件: SKILL.md, agents/, references/"

else
  # ─── 情况 2: 当前目录不存在 SKILL.md，需要克隆仓库 ───
  print_warning "当前目录未检测到 SKILL.md 文件"
  print_info "将从远程仓库克隆 eco-ai-native 项目..."
  echo ""

  # 检查是否已存在 eco-ai-native 目录
  if [[ -d "$CURRENT_DIR/eco-ai-native" ]]; then
    print_warning "检测到已存在 eco-ai-native 目录"
    read -p "是否删除并重新克隆? [y/N]: " -n 1 -r </dev/tty
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      print_info "删除现有目录..."
      rm -rf "$CURRENT_DIR/eco-ai-native"
    else
      print_info "跳过克隆，使用现有目录"
    fi
  fi

  # 克隆仓库
  if [[ ! -d "$CURRENT_DIR/eco-ai-native" ]]; then
    print_info "正在克隆仓库..."
    if ! git clone git@git.n.xiaomi.com:EcoAiNative/eco-ai-native.git "$CURRENT_DIR/eco-ai-native"; then
      print_error "克隆仓库失败"
      print_info "请检查:"
      print_info "  1. 网络连接是否正常"
      print_info "  2. 是否配置了 SSH 密钥"
      print_info "  3. 是否有访问仓库的权限"
      exit 1
    fi
    print_success "仓库克隆完成"
  fi

  # 切换到目标目录
  TARGET_DIR="$CURRENT_DIR/eco-ai-native/workflows/spec-power"

  if [[ ! -d "$TARGET_DIR" ]]; then
    print_error "目标目录不存在: $TARGET_DIR"
    print_info "请检查仓库结构是否正确"
    exit 1
  fi

  print_info "切换到目录: $TARGET_DIR"
  cd "$TARGET_DIR"

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 第一步：查找 install.sh 文件
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  print_info "第一步：查找 install.sh 文件..."

  if [[ ! -f "install.sh" ]]; then
    print_warning "当前分支未找到 install.sh 文件"
    print_info "尝试切换到 dev-sp 分支..."

    # 切换到 dev-sp 分支
    cd "$CURRENT_DIR/eco-ai-native"
    if git checkout dev-sp 2>/dev/null; then
      print_success "已切换到 dev-sp 分支"
      cd "$TARGET_DIR"

      # 再次检查 install.sh
      if [[ ! -f "install.sh" ]]; then
        print_error "dev-sp 分支中也未找到 install.sh 文件"
        print_info "正在清理临时文件..."
        cd "$CURRENT_DIR"
        rm -rf "$CURRENT_DIR/eco-ai-native"
        print_success "已清除临时仓库目录"
        exit 1
      fi

      print_success "在 dev-sp 分支中找到 install.sh 文件"
    else
      print_error "切换到 dev-sp 分支失败"
      print_info "正在清理临时文件..."
      cd "$CURRENT_DIR"
      rm -rf "$CURRENT_DIR/eco-ai-native"
      print_success "已清除临时仓库目录"
      exit 1
    fi
  else
    print_success "找到 install.sh 文件"
  fi

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # 第二步：验证 SKILL.md 文件
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  print_info "第二步：验证 SKILL.md 文件..."

  if [[ ! -f "SKILL.md" ]]; then
    print_error "未找到 SKILL.md 文件"
    print_info "正在清理临时文件..."
    cd "$CURRENT_DIR"
    rm -rf "$CURRENT_DIR/eco-ai-native"
    print_success "已清除临时仓库目录"
    exit 1
  fi

  print_success "找到 SKILL.md 文件"
  print_success "验证通过，准备执行安装脚本..."
  echo ""

  # 执行安装脚本
  bash "$TARGET_DIR/install.sh"

  # 检查安装结果
  INSTALL_EXIT_CODE=$?

  if [[ $INSTALL_EXIT_CODE -eq 0 ]]; then
    echo ""
    print_success "SpecPower 安装完成!"

    # 返回到原始目录
    cd "$CURRENT_DIR"

    # 清除克隆的仓库
    print_info "正在清理临时文件..."
    if rm -rf "$CURRENT_DIR/eco-ai-native"; then
      print_success "已清除临时仓库目录"
    else
      print_warning "清除临时目录失败，你可以手动删除: $CURRENT_DIR/eco-ai-native"
    fi
  else
    print_error "安装过程中出现错误"
    cd "$CURRENT_DIR"
    print_warning "保留克隆的仓库以供调试: $CURRENT_DIR/eco-ai-native"
    exit 1
  fi
fi

echo ""
print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "安装完成!"
print_info "你现在可以在支持的 AI 编辑器中使用 SpecPower"
print_info "详细使用方法请参考: SKILL.md"
print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
