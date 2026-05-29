// ==WindhawkMod==
// @id              zen-fileexplorer-transparent
// @name            ZenDesktop: File Explorer Transparent Background
// @description     Makes File Explorer folder background fully transparent - your desktop wallpaper shows through the file list area. Zero overhead, no background processes.
// @version         1.0.0
// @author          Lanbo
// @github          https://github.com/Liset999
// @include         explorer.exe
// @architecture    x86-64
// @compilerOptions -lcomctl32 -lole32 -loleaut32 -lruntimeobject -ldwmapi -lgdi32
// ==/WindhawkMod==

// ==WindhawkModReadme==
/*
# ZenDesktop: File Explorer Transparent Background

Makes the File Explorer folder background completely transparent so your
desktop wallpaper shows through the file list area. File icons and text
remain fully visible and functional.

### Key Features:
* **Wallpaper Through File List**: The area behind files and folders becomes
  transparent, letting your desktop wallpaper show through the Mica backdrop.
* **Zero Overhead**: Embedded natively inside explorer.exe. No background EXE,
  no taskbar icons, 0% CPU, virtually 0 MB extra RAM.
* **Process-Native Hooking**: Automatically subclasses File Explorer windows
  as they are created. Handles new windows, tabs, and Explorer restarts.
* **Safe & Compatible**: Uses native Win32 subclassing and DWM composition
  attributes. No XAML Diagnostics dependency. Compatible with Win11 22H2+.

### Notes
* The navigation pane and command bar areas retain their default backgrounds
  for readability - only the file listing area becomes transparent.
* Mica wallpaper backdrop is used to show your desktop wallpaper through
  the transparent areas. This is the standard Windows Mica material.
*/
// ==/WindhawkModReadme==

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <windhawk_utils.h>

#include <unordered_set>

// ==================== 消息常量 ====================

#define WM_DEFERRED_INIT (WM_APP + 0x100)  // 延迟初始化消息

// ==================== 全局状态 ====================

using CreateWindowExW_t = decltype(&CreateWindowExW);
CreateWindowExW_t Real_CreateWindowExW;

// 已处理的 CabinetWClass 窗口集合（避免重复应用）
std::unordered_set<HWND> g_processedCabinets;

// ==================== 子类化过程前向声明 ====================

LRESULT CALLBACK CabinetSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                     LPARAM lParam, DWORD_PTR dwRefData);
LRESULT CALLBACK ShellDefViewSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                          LPARAM lParam, DWORD_PTR dwRefData);
LRESULT CALLBACK ListViewSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                      LPARAM lParam, DWORD_PTR dwRefData);
LRESULT CALLBACK TransparentChildSubclassProc(HWND hWnd, UINT uMsg,
                                               WPARAM wParam, LPARAM lParam,
                                               DWORD_PTR dwRefData);

// ==================== 回调过程前向声明 ====================

BOOL CALLBACK EnumCabinetChildProc(HWND hChild, LPARAM lParam);
BOOL CALLBACK EnumWindowForUnsubclassProc(HWND hChild, LPARAM lParam);
BOOL CALLBACK EnumExistingExplorerProc(HWND hWnd, LPARAM lParam);

// ==================== DWM 工具函数 ====================

// 在 CabinetWClass 上保留 Mica 效果，让壁纸背景透出
void ApplyMicaToWindow(HWND hWnd)
{
    HMODULE hDwmApi = LoadLibraryExW(L"dwmapi.dll", nullptr,
                                      LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!hDwmApi)
        return;

    using DwmSetWindowAttribute_t = HRESULT(WINAPI*)(HWND, DWORD, LPCVOID, DWORD);
    auto pDwmSetWindowAttribute =
        (DwmSetWindowAttribute_t)GetProcAddress(hDwmApi, "DwmSetWindowAttribute");

    if (pDwmSetWindowAttribute)
    {
        // DWMWA_SYSTEMBACKDROP_TYPE = 102 (Win11 22H2+)
        // DWMSBT_MAINWINDOW = 2: 保留 Mica 效果
        DWORD backdropType = 2;
        pDwmSetWindowAttribute(hWnd, 102, &backdropType, sizeof(backdropType));
        Wh_Log(L"[ExplorerTP] Mica retained on %08X", (DWORD)(ULONG_PTR)hWnd);
    }

    FreeLibrary(hDwmApi);
}

// ==================== 透明化应用 ====================

void ApplyTransparencyToCabinet(HWND hCabinet)
{
    // 避免重复处理
    if (g_processedCabinets.count(hCabinet))
        return;
    g_processedCabinets.insert(hCabinet);

    Wh_Log(L"[ExplorerTP] Applying transparency to CabinetWClass: %08X",
           (DWORD)(ULONG_PTR)hCabinet);

    // Layer 1: 保留 Mica 壁纸背景
    ApplyMicaToWindow(hCabinet);

    // Layer 2: 枚举并处理所有子窗口
    EnumChildWindows(hCabinet, EnumCabinetChildProc, 0);

    // 强制主窗口重绘
    InvalidateRect(hCabinet, NULL, TRUE);
}

// Cabinet 子窗口枚举回调
BOOL CALLBACK EnumCabinetChildProc(HWND hChild, LPARAM lParam)
{
    (void)lParam;

    WCHAR szClass[128];
    if (!GetClassNameW(hChild, szClass, ARRAYSIZE(szClass)))
        return TRUE;

    if (wcscmp(szClass, L"SHELLDLL_DefView") == 0)
    {
        Wh_Log(L"[ExplorerTP] Subclassing SHELLDLL_DefView: %08X",
               (DWORD)(ULONG_PTR)hChild);
        WindhawkUtils::SetWindowSubclassFromAnyThread(
            hChild, ShellDefViewSubclassProc, 0);

        // 查找 SysListView32（实际文件列表区域）
        HWND hListView = FindWindowExW(hChild, NULL, L"SysListView32", NULL);
        if (hListView)
        {
            Wh_Log(L"[ExplorerTP] Transparent SysListView32: %08X",
                   (DWORD)(ULONG_PTR)hListView);
            ListView_SetBkColor(hListView, CLR_NONE);
            ListView_SetTextBkColor(hListView, CLR_NONE);
            WindhawkUtils::SetWindowSubclassFromAnyThread(
                hListView, ListViewSubclassProc, 0);
            InvalidateRect(hListView, NULL, TRUE);
        }
    }
    else if (wcscmp(szClass, L"DirectUIHWND") == 0 ||
             wcscmp(szClass, L"Windows.UI.Composition.DesktopWindowContentBridge") == 0 ||
             wcscmp(szClass, L"WorkerW") == 0)
    {
        WindhawkUtils::SetWindowSubclassFromAnyThread(
            hChild, TransparentChildSubclassProc, 0);
    }

    return TRUE;
}

// ==================== 子类化处理过程 ====================

// CabinetWClass 主窗口子类化
LRESULT CALLBACK CabinetSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                     LPARAM lParam, DWORD_PTR dwRefData)
{
    switch (uMsg)
    {
    case WM_DEFERRED_INIT:
        ApplyTransparencyToCabinet(hWnd);
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_NCDESTROY:
        g_processedCabinets.erase(hWnd);
        break;
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

// SHELLDLL_DefView 子类化（文件列表外壳）
LRESULT CALLBACK ShellDefViewSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                          LPARAM lParam, DWORD_PTR dwRefData)
{
    switch (uMsg)
    {
    case WM_ERASEBKGND:
        return 1;

    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN:
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX:
        SetBkMode((HDC)wParam, TRANSPARENT);
        return (LRESULT)GetStockObject(NULL_BRUSH);
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

// SysListView32 子类化（文件列表）
LRESULT CALLBACK ListViewSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                      LPARAM lParam, DWORD_PTR dwRefData)
{
    switch (uMsg)
    {
    case WM_ERASEBKGND:
        return 1;
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

// 通用透明子窗口子类化（DirectUIHWND, XAML 桥等）
LRESULT CALLBACK TransparentChildSubclassProc(HWND hWnd, UINT uMsg,
                                               WPARAM wParam, LPARAM lParam,
                                               DWORD_PTR dwRefData)
{
    switch (uMsg)
    {
    case WM_ERASEBKGND:
        return 1;
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

// ==================== CreateWindowExW Hook ====================

HWND WINAPI CreateWindowExW_Hook(
    DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName,
    DWORD dwStyle, int X, int Y, int nWidth, int nHeight,
    HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam)
{
    HWND hWnd = Real_CreateWindowExW(
        dwExStyle, lpClassName, lpWindowName, dwStyle,
        X, Y, nWidth, nHeight, hWndParent, hMenu, hInstance, lpParam);

    if (hWnd && lpClassName && !IS_INTRESOURCE(lpClassName))
    {
        if (wcscmp(lpClassName, L"CabinetWClass") == 0)
        {
            Wh_Log(L"[ExplorerTP] New CabinetWClass: %08X",
                   (DWORD)(ULONG_PTR)hWnd);

            WindhawkUtils::SetWindowSubclassFromAnyThread(
                hWnd, CabinetSubclassProc, 0);

            // 延迟初始化：等待子窗口创建完毕
            PostMessageW(hWnd, WM_DEFERRED_INIT, 0, 0);
        }
    }

    return hWnd;
}

// ==================== 处理已存在的窗口 ====================

BOOL CALLBACK EnumExistingExplorerProc(HWND hWnd, LPARAM lParam)
{
    (void)lParam;

    DWORD dwProcessId;
    GetWindowThreadProcessId(hWnd, &dwProcessId);

    if (dwProcessId != GetCurrentProcessId())
        return TRUE;

    WCHAR szClass[64];
    if (GetClassNameW(hWnd, szClass, ARRAYSIZE(szClass)) &&
        wcscmp(szClass, L"CabinetWClass") == 0)
    {
        WindhawkUtils::SetWindowSubclassFromAnyThread(
            hWnd, CabinetSubclassProc, 0);
        ApplyTransparencyToCabinet(hWnd);
    }

    return TRUE;
}

void ApplyToExistingExplorerWindows()
{
    EnumWindows(EnumExistingExplorerProc, 0);
}

// ==================== 清理函数 ====================

BOOL CALLBACK EnumWindowForUnsubclassProc(HWND hChild, LPARAM lParam)
{
    (void)lParam;

    WindhawkUtils::RemoveWindowSubclassFromAnyThread(
        hChild, ShellDefViewSubclassProc);
    WindhawkUtils::RemoveWindowSubclassFromAnyThread(
        hChild, ListViewSubclassProc);
    WindhawkUtils::RemoveWindowSubclassFromAnyThread(
        hChild, TransparentChildSubclassProc);

    return TRUE;
}

void UnsubclassAllWindows()
{
    for (HWND hCabinet : g_processedCabinets)
    {
        WindhawkUtils::RemoveWindowSubclassFromAnyThread(
            hCabinet, CabinetSubclassProc);

        EnumChildWindows(hCabinet, EnumWindowForUnsubclassProc, 0);

        InvalidateRect(hCabinet, NULL, TRUE);
    }

    g_processedCabinets.clear();
}

// ==================== Windhawk 入口点 ====================

BOOL Wh_ModInit()
{
    Wh_Log(L"[ExplorerTP] Initializing...");

    if (!Wh_SetFunctionHook(
            (void*)CreateWindowExW,
            (void*)CreateWindowExW_Hook,
            (void**)&Real_CreateWindowExW))
    {
        Wh_Log(L"[ExplorerTP] Failed to hook CreateWindowExW");
        return FALSE;
    }

    ApplyToExistingExplorerWindows();

    Wh_Log(L"[ExplorerTP] Initialized");
    return TRUE;
}

void Wh_ModAfterInit()
{
    Wh_Log(L"[ExplorerTP] AfterInit - reapplying...");
    ApplyToExistingExplorerWindows();
}

void Wh_ModUninit()
{
    Wh_Log(L"[ExplorerTP] Uninitializing...");
    UnsubclassAllWindows();
    Wh_Log(L"[ExplorerTP] Uninitialized");
}
