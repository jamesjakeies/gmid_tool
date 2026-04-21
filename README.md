# gmid_tool

MATLAB GUI 工具：通过读取工艺库模型文件（如 `.lib/.scs/.sp`）并提取常见模型参数，自动生成 **gm/Id** 相关曲线，用于模拟电路前期尺寸估算。

## 功能
- 读取 NMOS/PMOS 模型文件。
- 自动解析常见参数：`VTH0/U0/KP/TOX/COX/NFACTOR`。
- 基于 EKV 近似生成：
  - gm/Id vs Id/W
  - gm/Id vs IC
  - Id/W vs Vov
  - gm/Id target helper
- 支持曲线导出 CSV。

## 使用方式
在 MATLAB 命令行运行：

```matlab
gmid_gui
```

选择模型文件后点击 **Generate Curves**。

> 注意：该工具用于早期设计估算，最终结果应使用 PDK 官方仿真流程（Spectre/HSPICE 等）验证。
