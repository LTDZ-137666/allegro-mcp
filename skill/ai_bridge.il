; ai_bridge.il v3 -- Allegro AI Bridge (DLL 版本 + 聊天)
; 通过 C++ Bridge DLL (axlDllOpen) 建立 TCP 通信
; 聊天消息通过 bridge_chat_send/display_get 双向传输

unless(boundp('_ai_dll)  _ai_dll = nil)
unless(boundp('_ai_poll) _ai_poll = nil)
unless(boundp('_ai_respond) _ai_respond = nil)
unless(boundp('_ai_start) _ai_start = nil)
unless(boundp('_ai_stop) _ai_stop = nil)
unless(boundp('_ai_chat_send) _ai_chat_send = nil)
unless(boundp('_ai_display_get) _ai_display_get = nil)
unless(boundp('_ai_timer) _ai_timer = nil)
unless(boundp('_ai_chat_fw) _ai_chat_fw = nil)
unless(boundp('_ai_chat_hist) _ai_chat_hist = "")

; ============================================================
; DLL 加载
; ============================================================
procedure( _ai_load_dll()
    prog( ()
        _ai_dll = axlDllOpen("allegro_ai_bridge")
        unless(_ai_dll
            printf("AI Bridge: ERROR - Cannot load DLL\n")
            return(nil))
        _ai_start       = axlDllSym(_ai_dll "bridge_start")
        _ai_poll        = axlDllSym(_ai_dll "bridge_poll")
        _ai_respond     = axlDllSym(_ai_dll "bridge_respond")
        _ai_stop        = axlDllSym(_ai_dll "bridge_stop")
        _ai_chat_send   = axlDllSym(_ai_dll "bridge_chat_send")
        _ai_display_get = axlDllSym(_ai_dll "bridge_display_get")
        unless(_ai_poll && _ai_respond && _ai_start
            printf("AI Bridge: ERROR - symbol import failed\n")
            return(nil))
        printf("AI Bridge: DLL loaded\n")
        return(t)))

; 基于网表关系的局部聚类布局
; 计算元件 Place_Bound_Top 尺寸 (宽, 高), 找不到回退到引脚范围, 最小 80
procedure( _ai_sym_size(sym)
    let((w h pb found)
        found = nil
        ; 先尝试从 definition->children 找 Place_Bound_Top
        when(sym->definition && sym->definition->children
            foreach(c sym->definition->children
                when(c->layer == "PACKAGE GEOMETRY/PLACE_BOUND_TOP"
                    pb = c->bBox
                    when(pb
                        w = car(cadr(pb)) - car(car(pb))
                        h = cadr(cadr(pb)) - cadr(car(pb))
                        found = t))))
        ; 找不到则用引脚范围
        unless(found
            let((min_x max_x min_y max_y first)
                first = t
                foreach(p sym->pins
                    when(p->xy
                        if(first then
                            min_x = car(p->xy) max_x = car(p->xy)
                            min_y = cadr(p->xy) max_y = cadr(p->xy)
                            first = nil)
                        when(car(p->xy) < min_x  min_x = car(p->xy))
                        when(car(p->xy) > max_x  max_x = car(p->xy))
                        when(cadr(p->xy) < min_y  min_y = cadr(p->xy))
                        when(cadr(p->xy) > max_y  max_y = cadr(p->xy))))
                if(first then w = 80  h = 80
                    else w = max_x - min_x  h = max_y - min_y)))
        if(w < 50 then w = 80)
        if(h < 50 then h = 80)
        list(w h)))

procedure( _ai_cluster_around(refdes @optional gap)
    let((dsn sym all_nets net comps cx cy
         net_col g size w h cur_x cur_y dx dy total)
        g = if(gap then gap else 20)
        dsn = axlDBGetDesign()
        sym = nil
        foreach(s dsn->symbols  when(s->name == refdes  sym = s))
        unless(sym  return(nil))
        cx = car(sym->xy)  cy = cadr(sym->xy)
        size = _ai_sym_size(sym)  w = car(size)
        ; 收集非电源网络
        all_nets = nil
        foreach(p sym->pins
            when(p->net
                when(p->net->name != "GND" && p->net->name != "+14.4V" &&
                     p->net->name != "VCC3V3" && p->net->name != "VBAT+" &&
                     p->net->name != "VCC_3V3_MCU"
                    unless(memq(p->net all_nets)
                        all_nets = cons(p->net all_nets)))))
        ; 按网络分组排列
        total = 0  net_col = 0
        foreach(net all_nets
            comps = nil
            foreach(b net->branches
                foreach(c b->children
                    when(c->objType == "pin" && c->parent
                        comp = c->parent
                        when(comp->xy && comp != sym
                            unless(memq(comp comps)
                                comps = cons(comp comps))))))
            when(comps
                cur_x = net_col * (w + g)
                cur_y = 0
                foreach(s2 comps
                    size = _ai_sym_size(s2)
                    w2 = car(size)  h2 = cadr(size)
                    dx = cx + cur_x + w + g - car(s2->xy)
                    dy = cy + cur_y - cadr(s2->xy)
                    axlTransformObject(s2 ?move dx:dy)
                    cur_y = cur_y + h2 + g
                    total = total + 1)
                net_col = net_col + 1))
        sprintf(nil "Clustered %d comps in %d nets around %s" total net_col refdes)))

; 全板无干涉网格布局 (按 Place_Bound 尺寸紧密排列)
procedure( _ai_place_all(@optional gap)
    let((dsn all syms cur_x cur_y row_h w h g total size)
        g = if(gap then gap else 50)
        dsn = axlDBGetDesign()
        all = nil
        foreach(s dsn->symbols  when(s->xy  all = cons(s all)))
        syms = sortcar(all 'lessp)  ; 按 X 坐标排序
        total = 0  cur_x = 0  cur_y = 0  row_h = 0
        foreach(s2 syms
            size = _ai_sym_size(s2)
            w = car(size)  h = cadr(size)
            if(cur_x + w > 10000 then
                cur_x = 0  cur_y = cur_y + row_h + g  row_h = 0)
            axlTransformObject(s2 ?move cur_x - car(s2->xy) : cur_y - cadr(s2->xy))
            cur_x = cur_x + w + g
            if(h > row_h then row_h = h)
            total = total + 1)
        sprintf(nil "Placed %d components" total)))

axlCmdRegister("place_all" '_ai_place_all ?cmdType "general")
axlCmdRegister("cluster" '_ai_cluster_around ?cmdType "general")

; 给电源网表随机上色 (使用 axlCustomColorObject 分配实心颜色)
procedure( _ai_color_power_nets()
    let((dsn power_nets net color count)
        dsn = axlDBGetDesign()
        power_nets = list("GND" "+14.4V" "VCC3V3" "VBAT+" "VCC_3V3_MCU" "V_FB" "DC_EN")
        count = 0
        axlDBDisplayControl('customColorEnabled t)
        foreach(name power_nets
            foreach(n dsn->nets
                when(n->name == name
                    color = 1 + random(24)
                    axlCustomColorObject(n color)
                    printf("Colored %s = %d\n" name color)
                    count = count + 1)))
        sprintf(nil "Colored %d power nets" count)))

axlCmdRegister("color_power" '_ai_color_power_nets ?cmdType "general")

; ============================================================
; JSON 值序列化
; ============================================================
procedure( _ai_json_value(val)
    cond(
        (null(val) "null")
        (val == t  "true")
        (numberp(val) sprintf(nil "%L" val))
        (stringp(val) sprintf(nil "%L" val))
        (listp(val)
            let(((s "[")(first t))
                foreach(elem val
                    unless(first  s = strcat(s ","))
                    s = strcat(s _ai_json_value(elem))
                    first = nil)
                strcat(s "]")))
        (t sprintf(nil "\"%L\"" val))))

; ============================================================
; 命令执行
; ============================================================
procedure( _ai_execute(id method func_name expression params_json)
    let((result_list result_val)
        case(method
            ("raw"       result_list = errset(result_val = evalstring(expression)))
            ("evalstring" result_list = errset(result_val = evalstring(expression)))
            ("call_function"
                if(func_name == "" && expression != ""
                    result_list = errset(result_val = evalstring(expression))
                    result_list = errset(result_val = evalstring(strcat("(" func_name ")"))))))
        if(result_list then
            sprintf(nil "{\"id\":%d,\"result\":{\"success\":true,\"data\":%s},\"error\":null}"
                id _ai_json_value(result_val))
        else
            sprintf(nil "{\"id\":%d,\"result\":null,\"error\":{\"code\":-32603,\"message\":\"SKILL eval error\"}}"
                id))))

; ============================================================
; 定时器回调 -- 100ms
; ============================================================
procedure( _ai_poll_cb(window timerId elapsedTime)
    let((cmd_list cmd_id cmd_method cmd_func cmd_expr cmd_params result_json display_msg)
        cmd_list = axlDllCall(_ai_poll)

        when(cmd_list && listp(cmd_list) && length(cmd_list) >= 3
            cmd_id     = nthelem(1 cmd_list)
            cmd_method = nthelem(2 cmd_list)
            cmd_expr   = nthelem(4 cmd_list)
            result_json = _ai_execute(cmd_id cmd_method nthelem(3 cmd_list) cmd_expr nthelem(5 cmd_list))
            axlDllCall(_ai_respond cmd_id result_json)
        )

        ; 没有命令但有聊天待发 → 发空响应推动聊天消息到 Python
        unless(cmd_list
            when(_ai_chat_send
                axlDllCall(_ai_respond 0 "{\"result\":\"chat_ping\"}")
            )
        )

        ; 检查 Python 发来的显示消息
        when(_ai_display_get
            display_msg = axlDllCall(_ai_display_get)
            when(display_msg && stringp(display_msg)
                _ai_chat_display(display_msg)
            )
        )
    )
)

; ============================================================
; AI 聊天窗口 -- inline form
; ============================================================
_ai_chat_form_def = '("
	FILE_TYPE=FORM_DEFN VERSION=2
	FORM
	FIXED
	PORT 62 28
	HEADER \"AI Chat\"

	TILE

	TEXT \"Output:\"
	TLOC 2 1
	ENDTEXT

	FIELD output
	FLOC 2 2
	STRFILLIN 58 4096
	FSIZE 58 18
	ENDFIELD

	TEXT \"Command:\"
	TLOC 2 21
	ENDTEXT

	FIELD input
	FLOC 2 22
	STRFILLIN 46 256
	ENDFIELD

	FIELD send
	FLOC 50 22
	MENUBUTTON \"Send\" 5 2
	ENDFIELD

	FIELD close
	FLOC 56 22
	MENUBUTTON \"Close\" 5 2
	ENDFIELD

	ENDTILE

	ENDFORM
")

procedure( _ai_chat_cb(fw)
    let((input)
        case(fw->curField
            ("send"
                input = axlFormGetField(fw "input")
                when(and(input nequal(input ""))
                    _ai_chat_hist = strcat(_ai_chat_hist ">>> " input "\n")
                    axlDllCall(_ai_chat_send input)
                    _ai_chat_hist = strcat(_ai_chat_hist "...waiting...\n\n")
                    axlFormSetField(fw "output" _ai_chat_hist)
                    axlFormSetField(fw "input" "")))
            ("close"  axlFormClose(fw)  _ai_chat_fw = nil))))

procedure( _ai_chat_display(msg)
    when(_ai_chat_fw
        _ai_chat_hist = strcat(_ai_chat_hist msg "\n\n")
        axlFormSetField(_ai_chat_fw "output" _ai_chat_hist))
    when(not(_ai_chat_fw)  printf("AI: %s\n" msg)))

procedure( _ai_chat_open()
    let((fw)
        fw = axlFormCreate('_ai_chat_fw list("aichat" _ai_chat_form_def)
            '("msgLines" 0) '_ai_chat_cb t)
        when(fw
            _ai_chat_hist = "AI Chat ready.\nType SKILL expr or natural language\n\n"
            axlFormSetField(fw "output" _ai_chat_hist)
            axlFormDisplay(fw))))

axlCmdRegister("ai_chat" '_ai_chat_open ?cmdType "general")

; ============================================================
; 辅助函数
; ============================================================
procedure( _ai_net_pins(netName)
    let((dsn net pins)
        dsn = axlDBGetDesign()
        foreach(n dsn->nets  when(n->name == netName  net = n))
        unless(net  return(nil))
        pins = nil
        foreach(b net->branches
            foreach(p b->children
                when(p->objType == "pin"  pins = cons(p->xy pins))))
        pins))

procedure( _ai_route(netName layer x1 y1 x2 y2 @optional (width 5))
    axlDBCreateLine(list(x1:y1 x2:y2) width layer netName))

procedure( _ai_route_net(netName @optional (layer "ETCH/TOP") (width 5))
    let((pins sorted i p1 p2)
        pins = _ai_net_pins(netName)
        unless(pins  return(nil))
        if(length(pins) < 2 then return(nil))
        sorted = sortcar(pins 'lessp)
        for(i 0 length(sorted)-2
            p1 = nthelem(i+1 sorted)
            p2 = nthelem(i+2 sorted)
            _ai_route(netName layer width car(p1) cadr(p1) car(p2) cadr(p2)))
        t))

procedure( _ai_delete_routes(netName)
    let((net)
        foreach(n axlDBGetDesign()->nets  when(n->name == netName  net = n))
        when(net
            foreach(b net->branches
                foreach(c b->children
                    when(c->objType == "cline"  axlDeleteObject(c)))))))

; ============================================================
; 启动/停止
; ============================================================
procedure( ai_server_start(@optional (port 57123))
    unless(_ai_dll  unless(_ai_load_dll() return(nil)))
    axlDllCall(_ai_start port)
    unless(_ai_timer  _ai_timer = axlUIWTimerAdd(nil 100 nil '_ai_poll_cb))
    printf("AI Bridge: Server started on port %d\n" port)
    t)

procedure( ai_server_stop()
    when(_ai_timer  axlUIWTimerRemove(_ai_timer)  _ai_timer = nil)
    when(_ai_stop  axlDllCall(_ai_stop))
    printf("AI Bridge: Server stopped\n")
    t)

; 自动加载瓶颈检测模块
when(isFile("bottleneck.il") loadi("bottleneck.il"))

; 创建填充矩形 shape (x1 y1 = 左下角, x2 y2 = 右上角)
procedure( _ai_create_rect(x1 y1 x2 y2 @optional layer)
    unless(layer layer = "BOARD GEOMETRY/SILKSCREEN_TOP")
    axlDBCreateRectangle(list(x1:y1 x2:y2) t layer nil nil)
)
axlCmdRegister("ai_rect" '_ai_create_rect ?cmdType "general")

axlCmdRegister("ai_server_start"  'ai_server_start  ?cmdType "general")
axlCmdRegister("ai_server_stop"   'ai_server_stop   ?cmdType "general")

printf("AI Bridge v3 (DLL+Chat) loaded.\n")
printf("  ai_server_start    -- start bridge\n")
printf("  ai_server_stop     -- stop bridge\n")
printf("  ai_chat            -- open AI chat window\n")
printf("  ai_bottleneck NET  -- scan copper bottlenecks\n")
