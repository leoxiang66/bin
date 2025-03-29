#!/bin/bash

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 或以 root 用户运行此脚本"
    exit 1
fi

# 安装必要工具
apt-get update
apt-get install -y dpkg-dev patchelf

# 交互式输入基本信息
read -p "请输入二进制文件路径（如 /path/to/binary）: " BINARY_PATH
read -p "请输入输出 .deb 包名称（如 myapp）: " PKG_NAME
read -p "请输入版本号（如 1.0.0）: " PKG_VERSION
read -p "请输入维护者信息（如 Your Name <your.email@example.com>）: " PKG_MAINTAINER
read -p "请输入软件包描述（单行描述）: " PKG_DESCRIPTION

# 检查是否为GUI应用程序
IS_GUI_APP="n"
read -p "这是一个GUI应用程序吗？需要创建桌面入口吗？(y/n) [n]: " IS_GUI_APP
IS_GUI_APP=${IS_GUI_APP:-n}

# 如果是GUI应用，收集额外信息
if [[ "$IS_GUI_APP" =~ ^[yY] ]]; then
    read -p "请输入应用程序名称（显示在菜单中的名称）: " APP_NAME
    read -p "请输入图标文件路径（可选，留空则无图标）: " ICON_PATH
    
    # 验证图标文件是否存在
    if [ -n "$ICON_PATH" ] && [ ! -f "$ICON_PATH" ]; then
        echo "警告: 图标文件不存在，将不使用图标"
        ICON_PATH=""
    fi
    
    # 询问应用程序类别
    echo "请选择应用程序类别（输入数字）:"
    echo "1. Development"
    echo "2. Education"
    echo "3. Game"
    echo "4. Graphics"
    echo "5. Network"
    echo "6. Office"
    echo "7. Science"
    echo "8. Settings"
    echo "9. System"
    echo "10. Utility"
    read -p "选择 [6]: " CATEGORY_NUM
    
    case $CATEGORY_NUM in
        1) CATEGORY="Development" ;;
        2) CATEGORY="Education" ;;
        3) CATEGORY="Game" ;;
        4) CATEGORY="Graphics" ;;
        5) CATEGORY="Network" ;;
        6) CATEGORY="Office" ;;
        7) CATEGORY="Science" ;;
        8) CATEGORY="Settings" ;;
        9) CATEGORY="System" ;;
        10) CATEGORY="Utility" ;;
        *) CATEGORY="Office" ;;
    esac
fi

# 检查二进制文件
if [ ! -f "$BINARY_PATH" ]; then
    echo "错误：二进制文件不存在！"
    exit 1
fi

# 定义系统库标准路径（扩展版）
SYSTEM_LIB_PATHS=(
    "/lib"
    "/lib64"
    "/usr/lib"
    "/usr/lib64"
    "/usr/local/lib"
    "/usr/lib/x86_64-linux-gnu"
)

# 创建工作目录
WORK_DIR="${PKG_NAME}_${PKG_VERSION}_amd64"
mkdir -p "$WORK_DIR/DEBIAN"
mkdir -p "$WORK_DIR/usr/bin"
mkdir -p "$WORK_DIR/usr/lib"

# 如果是GUI应用，创建必要的目录
if [[ "$IS_GUI_APP" =~ ^[yY] ]]; then
    mkdir -p "$WORK_DIR/usr/share/applications"
    mkdir -p "$WORK_DIR/usr/share/icons/hicolor/256x256/apps"
    
    # 复制图标文件（如果有）
    if [ -n "$ICON_PATH" ]; then
        ICON_EXT="${ICON_PATH##*.}"
        ICON_NAME="${PKG_NAME}.${ICON_EXT}"
        cp "$ICON_PATH" "$WORK_DIR/usr/share/icons/hicolor/256x256/apps/$ICON_NAME"
    fi
fi

# 复制二进制文件
BINARY_NAME=$(basename "$BINARY_PATH")
cp "$BINARY_PATH" "$WORK_DIR/usr/bin/"
chmod 755 "$WORK_DIR/usr/bin/$BINARY_NAME"

# 检测依赖库并分类处理
echo "正在分析依赖库..."
DEPS=$(ldd "$BINARY_PATH" | awk 'NF == 4 {print $3}; NF == 2 {print $1}' | sort -u)

SYSTEM_DEPS=""
THIRD_PARTY_LIBS=""

for LIB in $DEPS; do
    if [ -f "$LIB" ]; then
        # 检查是否为系统库
        is_system_lib=0
        for SYS_PATH in "${SYSTEM_LIB_PATHS[@]}"; do
            if [[ "$LIB" == "$SYS_PATH"* ]]; then
                # 获取包名并去重
                PKG=$(dpkg -S "$LIB" 2>/dev/null | cut -d: -f1 | head -1)
                if [ -n "$PKG" ] && [[ ! "$SYSTEM_DEPS" =~ "$PKG" ]]; then
                    SYSTEM_DEPS+="$PKG,"
                fi
                is_system_lib=1
                break
            fi
        done

        # 非系统库处理
        if [ $is_system_lib -eq 0 ]; then
            LIB_NAME=$(basename "$LIB")
            cp "$LIB" "$WORK_DIR/usr/lib/"
            if [[ ! "$THIRD_PARTY_LIBS" =~ "$LIB_NAME" ]]; then
                THIRD_PARTY_LIBS+="$LIB_NAME,"
            fi
            echo "已复制第三方库: $LIB -> /usr/lib/$LIB_NAME"
        fi
    fi
done

# 清理依赖列表：去除重复和连续逗号
SYSTEM_DEPS=$(echo "$SYSTEM_DEPS" | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
THIRD_PARTY_LIBS=$(echo "$THIRD_PARTY_LIBS" | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')

# 生成 control 文件
cat > "$WORK_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: $PKG_MAINTAINER
Depends: ${SYSTEM_DEPS}
Description: $PKG_DESCRIPTION
EOF

# 如果是GUI应用，创建.desktop文件
if [[ "$IS_GUI_APP" =~ ^[yY] ]]; then
    DESKTOP_FILE="$WORK_DIR/usr/share/applications/${PKG_NAME}.desktop"
    
    # 设置图标路径（如果有）
    ICON_LINE=""
    if [ -n "$ICON_PATH" ]; then
        ICON_LINE="Icon=/usr/share/icons/hicolor/256x256/apps/$ICON_NAME"
    fi
    
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=$PKG_DESCRIPTION
Exec=/usr/bin/$BINARY_NAME
$ICON_LINE
Categories=$CATEGORY;
Terminal=false
StartupNotify=true
EOF
    
    chmod 644 "$DESKTOP_FILE"
fi

# 设置 rpath 确保程序能找到第三方库
patchelf --set-rpath '/usr/lib' "$WORK_DIR/usr/bin/$BINARY_NAME"

# 构建 .deb 包
dpkg-deb --build --root-owner-group "$WORK_DIR"
echo "已生成 $WORK_DIR.deb"

# 结果摘要
echo -e "\n===== 打包结果 ====="
echo "包名称: $PKG_NAME"
echo "版本号: $PKG_VERSION"
echo "维护者: $PKG_MAINTAINER"
echo "描述: $PKG_DESCRIPTION"
echo "系统依赖: ${SYSTEM_DEPS}"
if [ -n "$THIRD_PARTY_LIBS" ]; then
    echo "内置第三方库: ${THIRD_PARTY_LIBS}"
else
    echo "未包含第三方库"
fi

if [[ "$IS_GUI_APP" =~ ^[yY] ]]; then
    echo -e "\n===== 应用程序信息 ====="
    echo "应用程序名称: $APP_NAME"
    echo "桌面入口文件: /usr/share/applications/${PKG_NAME}.desktop"
    if [ -n "$ICON_PATH" ]; then
        echo "应用程序图标: /usr/share/icons/hicolor/256x256/apps/$ICON_NAME"
    else
        echo "未指定应用程序图标"
    fi
    echo "应用程序类别: $CATEGORY"
fi