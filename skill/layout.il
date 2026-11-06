; layout.il -- 按网络自动布局

; 获取网络上所有元件（去重），返回元件列表
procedure( _ai_net_components(net)
    let((comps comp)
        comps = nil
        foreach(b net->branches
            foreach(c b->children
                when(c->objType == "pin" && c->parent
                    comp = c->parent
                    when(comp->xy  unless(memq(comp comps) comps = cons(comp comps))))))
        comps))

; 按当前 X 坐标排序元件
procedure( _ai_sort_by_x(comps)
    let((pairs)
        pairs = nil
        foreach(c comps  pairs = cons(list(car(c->xy) c) pairs))
        sortcar(pairs 'lessp)))

; 水平一字排列单个网络的所有元件
; 用法: place_net("MCU_NRST") -- 按当前坐标自动布局
;       place_net("MCU_NRST" startX startY gap) -- 指定起始点和间距
procedure( _ai_place_net(netName @optional (startX nil) (startY nil) (g 20))
    let((net comps sorted cx cy i x y comp w h size)
        ; 1. 找网络
        net = nil
        foreach(n axlDBGetDesign()->nets  when(n->name == netName  net = n))
        unless(net  return(sprintf nil "Net %s not found" netName))
        ; 2. 收集元件
        comps = _ai_net_components(net)
        unless(comps  return(sprintf nil "No components on net %s" netName))
        ; 3. 按X排序
        sorted = _ai_sort_by_x(comps)
        ; 4. 起始位置: 默认用第一个元件的当前位置
        when(null(startX)  startX = car(car(car(sorted))->xy))
        when(null(startY)  startY = cadr(car(car(sorted))->xy))
        cx = if(numberp(startX) startX car(car(car(sorted))->xy))
        cy = if(numberp(startY) startY cadr(car(car(sorted))->xy))
        ; 5. 逐个放置（一字排列，间隙用 Place_Bound 算出）
        i = 0  x = cx
        foreach(pair sorted
            comp = cadr(pair)
            size = _ai_sym_size(comp)
            w = car(size)
            axlTransformObject(comp ?move x - car(comp->xy) : cy - cadr(comp->xy))
            x = x + w + g
            i = i + 1)
        sprintf(nil "Placed %d comps for net %s" i netName)))

; 获取元件尺寸（从 Place_Bound_Top，回退到引脚范围，最小80mil）
procedure( _ai_sym_size(sym)
    let((w h pb found c)
        w = 80  h = 80  found = nil
        when(sym->definition && sym->definition->children
            foreach(c sym->definition->children
                when(c->layer == "PACKAGE GEOMETRY/PLACE_BOUND_TOP"
                    pb = c->bBox
                    when(pb
                        w = car(cadr(pb)) - car(car(pb))
                        h = cadr(cadr(pb)) - cadr(car(pb))
                        found = t))))
        unless(found
            let((min_x max_x min_y max_y first p)
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
                unless(first  w = max_x - min_x  h = max_y - min_y)))
        if(w < 50 then w = 80)
        if(h < 50 then h = 80)
        list(w h)))

; 一键布局所有非电源信号网络
procedure( _ai_place_all_nets(@optional gap)
    let((nets done_comp done_nets g)
        g = if(gap then gap else 15)
        nets = nil  done_nets = nil
        ; 收集所有网络（排除GND和电源）
        foreach(n axlDBGetDesign()->nets
            when(n->name != "GND" && n->name != "+14.4V" &&
                 n->name != "VCC3V3" && n->name != "VBAT+" &&
                 n->name != "VCC_3V3_MCU" && n->name != "V_FB" && n->name != "DC_EN"
                ; 只处理有至少2个元件的网络
                when(length(_ai_net_components(n)) >= 2
                    nets = cons(n nets))))
        ; 从板框左上+50mil开始
        bbox = axlDBGetDesign()->bBox
        cur_x = car(car(bbox)) + 50
        cur_y = cadr(cadr(bbox)) - 50
        max_x = car(cadr(bbox)) - 50
        row_h = 0  total = 0
        foreach(n2 nets
            comps = _ai_net_components(n2)
            when(comps
                sorted = _ai_sort_by_x(comps)
                foreach(sp sorted
                    comp = cadr(sp)
                    size = _ai_sym_size(comp)
                    w = car(size)  h = cadr(size)
                    when(cur_x + w > max_x
                        cur_x = car(car(bbox)) + 50
                        cur_y = cur_y - row_h - g  row_h = 0)
                    axlTransformObject(comp ?move cur_x - car(comp->xy) : cur_y - cadr(comp->xy))
                    cur_x = cur_x + w + g
                    when(h > row_h  row_h = h)
                    total = total + 1)))
        sprintf(nil "Placed %d components from %d nets" total length(nets))))

axlCmdRegister("place_net" '_ai_place_net ?cmdType "general")
axlCmdRegister("place_all" '_ai_place_all_nets ?cmdType "general")
printf("Layout loaded. Commands: place_net <name>, place_all\n")
