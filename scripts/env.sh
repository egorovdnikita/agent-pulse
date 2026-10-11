# Общие флаги SwiftPM. Подключается через `source`.
#
# Без Xcode (только Command Line Tools) новый бэкенд SwiftPM падает на plist,
# а Swift Testing не находится без явного пути к фреймворку.
SWIFT_FLAGS=(--build-system native)

CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* && -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
    TEST_FLAGS=(-Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS")
else
    TEST_FLAGS=()
fi
