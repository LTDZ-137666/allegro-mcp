; grid_setter.il — 弹出便携窗口，点选即切换设计单位 + 更改 Grid 大小
; 用法: loadi("grid_setter.il") 然后命令 gridset
; 两栏单选: mil (5~400) 和 mm (0.1~2)
; 点 mil → 设计单位切到 mils，grid 设 mil 值
; 点 mm → 设计单位切到 millimeters，grid 设 mm 值
; 跨单位联动: 点 mm 自动清空 mil 选中，反之亦然

; 全局状态
unless(boundp('_grid_fw)  _grid_fw = nil)

; 两组单选字段名
_grid_mil_fields = list("rb_m5" "rb_m10" "rb_m12" "rb_m25" "rb_m50" "rb_m100" "rb_m200" "rb_m400")
_grid_mm_fields  = list("rb_mm_01" "rb_mm_02" "rb_mm_025" "rb_mm_05" "rb_mm_1" "rb_mm_2")

; mil 选项对应的 grid 值
_grid_mil_map = list(
    "rb_m5" "5"   "rb_m10" "10"  "rb_m12" "12.5" "rb_m25" "25"
    "rb_m50" "50" "rb_m100" "100" "rb_m200" "200" "rb_m400" "400"
)
; mm 选项对应的值
_grid_mm_map = list(
    "rb_mm_01" "0.1"  "rb_mm_02" "0.2"  "rb_mm_025" "0.25"
    "rb_mm_05" "0.5" "rb_mm_1" "1.0"   "rb_mm_2" "2.0"
)

; 在 key/value 对列表中按 key 查找 value (替代 assoc)
procedure( _grid_lookup(key kvs)
    let((idx)
        idx = member(key kvs)
        when(idx && cadr(idx) cadr(idx))
    )
)

; ============================================================
; 切换设计单位 (mils -> 1精度, millimeters -> 4精度)
; 切换前临时关闭 DRC 避免重复检查卡顿，完成后恢复
; ============================================================
procedure( _grid_set_units(units)
    let((old_drc result)
        old_drc = axlDBControl('drcEnable nil)
        result = cond(
            (units == "mils"         axlDBChangeDesignUnits("mils" 1))
            (units == "millimeters"  axlDBChangeDesignUnits("millimeters" 4))
            (t nil))
        axlDBControl('drcEnable old_drc)
        result)
)

; ============================================================
; 将所有层的 grid 设为指定值 (按当前设计单位)
; ============================================================
procedure( _grid_set_all(val)
    let((g grids grid changed)
        g = if(numberp(val) val atof(val))
        if(g && g > 0.0 then
            changed = 0
            foreach(n axlDBGridGet(nil)
                grid = axlDBGridGet(n)
                when(grid
                    grid->xGrids = g
                    grid->yGrids = g
                    when(axlDBGridSet(grid) changed = changed + 1)))
            printf("Grid Setter: set %L on %d grid(s)\n" g changed)
            axlDBDisplayControl('gridVisible t)
            t
        else
            printf("Grid Setter: invalid value '%s'\n" val)
            nil)
    )
)

; ============================================================
; 清空一组单选
; ============================================================
procedure( _grid_clear(fw fields)
    foreach(f fields axlFormSetField(fw f nil))
    t
)

; ============================================================
; Form 回调 — 点选即生效
; ============================================================
procedure( _grid_cb(fw)
    let((val cf)
        cf = fw->curField
        when(cf
            cond(
                (cf == "close"
                    axlFormClose(fw)
                    _grid_fw = nil)
                (cf == "custom_size"
                    val = axlFormGetField(fw "custom_size")
                    when(val && val != ""
                        _grid_clear(fw _grid_mil_fields)
                        _grid_clear(fw _grid_mm_fields)
                        _grid_set_all(val)))
                (t
                    ; 查 mil 组
                    val = _grid_lookup(cf _grid_mil_map)
                    when(val
                        ; 点 mil → 设计单位切 mils + 清空 mm 组 + 设值
                        _grid_set_units("mils")
                        _grid_clear(fw _grid_mm_fields)
                        _grid_set_all(val))
                    ; 查 mm 组 (未命中 mil 时)
                    unless(val
                        val = _grid_lookup(cf _grid_mm_map)
                        when(val
                            ; 点 mm → 设计单位切 mm + 清空 mil 组 + 设值
                            _grid_set_units("millimeters")
                            _grid_clear(fw _grid_mil_fields)
                            _grid_set_all(val))))
            )
        )
    )
)

; ============================================================
; 打开窗口
; ============================================================
procedure( grid_setter_open()
    let((fw units is_mm formPath)
        printf("Grid Setter: creating form...\n")
        ; form path: GRID_SETTER_FORM env var, else %HOME%/pcbenv/
        formPath = getShellEnvVar("GRID_SETTER_FORM")
        unless(formPath
            formPath = strcat(getShellEnvVar("HOME") "/pcbenv/grid_setter.form")
        )
        fw = axlFormCreate('_grid_fw formPath nil '_grid_cb t)
        printf("Grid Setter: form=%L\n" fw)
        if(fw then
            ; 根据当前设计单位选中对应组
            units = car(axlDBGetDesignUnits())
            is_mm = units == "millimeters"
            if(is_mm then
                axlFormSetField(fw "rb_mm_05" t)
            else
                axlFormSetField(fw "rb_m25" t))
            axlFormDisplay(fw)
            printf("Grid Setter: form displayed (%s)\n" units)
        else
            printf("Grid Setter: ERROR - form creation failed\n"))
    )
)

axlCmdRegister("gridset" 'grid_setter_open ?cmdType "general")
printf("grid_setter.il loaded. Command: gridset\n")
