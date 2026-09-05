# 核心实现接口 v1

工作区：D:/game/GameDev/Projects/Grow/.worktrees/grow-p0。所有实现者只写获分配文件，Git 提交由主代理执行。改既有文件必须先 tools/safe_write.py 迁移原件并记录日志；可用其 write_file(path,text) 完成备份后写入。不可删除文件。

## PlantState（scripts/core/plant_state.gd）

extends RefCounted，不依赖场景树。建议 consumers preload 文件而非依赖 class_name 导入缓存。除 Vector2 外，仅使用可深拷贝的 Dictionary/Array/string/number/bool。

- 属性 energy=30.0, revision=0, next_id=2, tick=0, seed_id=1。
- nodes: Dictionary，整数ID到 `{id:int, pos:Vector2, parent_edge:int(种子0), kind:String(seed/root/shoot), anchor:Dictionary(无则{}), emergency:bool}`。
- edges: Dictionary，整数ID到 `{id:int,a:int,b:int,kind:String(root/vine/branch),length:float,points:Array[Vector2],z:float,bend:float,emergency:bool,slot:int}`。points含首尾，≤.05u采样。
- leaves: Dictionary，整数ID到 `{id:int,node:int,angle:float,z:float,emergency:bool,produced:float}`。叶的逻辑中心为挂点＋沿 angle 方向 .16u，半长.20、半宽.10，angle 用逻辑弧度。
- history:Array（失活边/叶的完整快照，含reason）；scars:Dictionary（key为node:slot，值含issued、consumed、pos等）；events:Array；explored:Array[Vector2]；revealed:Array[String]。
- emergency_produced=0.0, rescue_count=0, victory_time=0.0, won=false, dry_hint_time=0.0。
- `static func create(seed_position:Vector2=Vector2(2,-0.8))` 返回新状态。
- `func clone()` 深拷贝所有持久状态。
- `func add_edge(a:int,kind:String,points:Array,anchor:Dictionary={},emergency:bool=false,slot:int=0)->int` 分配边和末端节点ID，返回边ID；length为折线长度。
- `func add_leaf(node:int,angle:float=0.8,emergency:bool=false)->int` 返回叶ID。
- `func children(node:int,kind:String="")->Array` 返回按ID排序的出边字典，kind空返回全部。
- `func leaf_at(node:int,include_emergency:bool=false)->int` 返回叶ID，未找到0。
- `func validate()->Array[String]` 检查ID唯一、seed、树连通/环、父边对应、有限数、上限、E范围。
- 基础增删只建立数据，经济和合法性由 CommandService 处理。全部ID全局唯一，preview clone上的临时ID不消耗事实状态。

## Environment / GrowthSolver（独立几何模块）

- `Environment.new()` 默认第一章；属性 soils:Array[Rect2], obstacles:Array[{id,rect:Rect2}], surfaces:Array[{id,a:Vector2,b:Vector2}], waters:Array[{id,aquifer_id,q,rect:Rect2}], lights:Array[{id,rect:Rect2,intensity:float,direction:Vector2}], clues:Array[{id,pos:Vector2}], exit_rect:Rect2。
- Rect2 使用逻辑坐标最小x/y和正宽高。静态数据不随预览更改。
- `root_allowed(points:Array,radius:float=0.025)->bool` 完整扫掠须在土壤或裂缝内。
- `blocked(points:Array,radius:float)->bool` 对矩形硬障碍作带半径扫掠，薄墙不可穿。
- `anchor_at(point:Vector2,direction:Vector2)->Dictionary` 返回允许表面 `{id,pos,normal}` 或{}；夹角≤25°、距离≤.12。
- `water_contacts(state)->Array` 返回活根接点 `{node:int,access_id:String,aquifer_id:String,q:float}`，多接同源允许但Q不相加。
- `light_at(point:Vector2)->Dictionary` 最强光区或 `{intensity:0.0,direction:Vector2.UP,id:"dark"}`；direction指向光源，R0不在普通lights中。
- `ray_blocked(from:Vector2,to:Vector2)->bool` 建筑遮挡；叶遮挡由光求解器负责。
- `stimulus(state,origin:Vector2,kind:String)->Vector2` 已感知光/水方向，根只用2.4u内线索。
- `reveal(state,position:Vector2)` 仅在提交后记录地下探索和1.2u内clues。
- `GrowthSolver.build(state,env,node_id:int,kind:String,direction:Vector2)->Dictionary` 纯预览，返回 `{ok:bool,reason:String,points:Array,anchor:Dictionary}`，失败也可携带points。段长/曲线/偏转按TDD第5节，固定state.next_id生成可复现微偏。根合法土壤与碰撞、藤碰撞，端点吸附后须完整复核，不用修改state。

## WaterSolver / SupportSolver / LightSolver（纯求解）

- `WaterSolver.solve(state,accesses:Array)->Dictionary` 返回 `{q:float,demand:float,spent:float,organs:Dictionary}`。organs键为边或叶ID，值 `{r:float,resistance:float,demand:float,delivered:float,spent:float,base:float}`。emergency叶需水.2，produced>=18休眠后需水0。水路每边中点/叶挂点，排序根→枝→藤→叶。无水时r=0、resistance可用有限哨值而非INF；输出不能含NaN/INF。死亡或历史不参与。
- `SupportSolver.solve(state)->Dictionary` 返回 `{max_risk:float,organs:Dictionary}`，每地上边 `{risk:float,distance:float,moment:float}`。根不参与、端点有效anchor切断负载；叶重.25；应急叶由种子固定不向常规枝传播。
- `LightSolver.solve(state,env)->Dictionary` 返回以叶ID为键的字典，每值 `{light:float,transmission:float,intensity:float}`。这里只算几何光，无需水/健康；应急叶固定light1，收入由Simulation按1E/s单独处理。

## CommandService / Simulation（后续消费者）

- Service.new(initial_state,environment)，公开state/env，`preview(kind:String,target:int,direction:Vector2=Vector2.ZERO)->Dictionary` 与 `commit(preview:Dictionary,command_id:String)->Dictionary`；预览含ok/reason/cost/revision/candidate/points、水、结构、光与失活统计。新生成成功才替换state；失败不能消耗或揭示。commit同ID去重。
- preview kind: root/vine/leaf/reinforce/prune_edge/prune_leaf/rescue。
- Simulation.new(service)，`set_frozen(reason:String,enabled:bool)`，`advance(real_dt:float,fast:bool=false,target_cost:float=5.0)`；`step(dt:float)`仅测试/固定回放使用。simulation.metrics保存水/光/结构/总income，供UI读。

## 测试协作

每模块独立 tests/test_*.gd extends RefCounted；`func run(t)` 调用 `t.check(condition,message)` / `t.near(actual,expected,tolerance,message)`。入口 tests/run_tests.gd 支持 `-- --suite=solvers` 等，仅载入指定模块；默认扫所有test_*.gd。所有动态对象方法调用的接收变量用 `var value =`，必要时明确类型，避免 Variant 推断警告导致Godot解析失败。

必须先编写并运行测试显示预期失败，再实现。报告记录测试命令、失败原因、通过数与关注事项到 docs/development/reports/ 对应文件。不要虚构窗口/性能/导出验收。
