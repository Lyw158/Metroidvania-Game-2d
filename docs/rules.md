为了项目之间的一致性，我们建议遵循以下规范：

使用 snake_case 风格为文件夹和文件命名(除了c#脚本). 这避免了在 Windows 上导出项目时可能出现的大小写敏感问题.C# 脚本是这个规则的一个例外, 因为按照惯例是用类名来对它们命名, 而类名应该是 PascalCase 风格.

使用 PascalCase 风格对节点进行命名, 这与内置的节点大小写风格一致.

通常, 将第三方资源放在顶级的 addons/ 文件夹中, 即使它们不是编辑器插件. 这样更加容易跟踪哪些文件是第三方文件. 当然这个规则也有一些例外: 如果你要使用第三方游戏资源创建角色, 将这些资源和角色场景及脚本放在同一文件夹下会更好.

版本控制介绍见
https://docs.godotengine.org/zh-cn/4.x/tutorials/best_practices/version_control_systems.html