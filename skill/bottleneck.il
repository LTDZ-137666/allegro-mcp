; bottleneck.il -- scanline copper width analysis + silkscreen annotation
; Usage: loadi("bottleneck.il")
;        ai_bottleneck("5V" 30 80 t)      ; 30 slices, 80mil threshold, draw=yes
;        ai_bottleneck("5V" 50 60 nil)     ; 50 slices, 60mil threshold, analyze only

procedure( ai_bottleneck(netName nSlices threshold draw)
  let((net shape segs edges i n y1 y2 x1 x2 y_min y_max step
       scan_y xs j width slices prev_w next_w narrow total
       rs re rw merged y_curr w_curr)
    net = nil
    foreach(n2 axlDBGetDesign()->nets when(n2->name == netName net = n2))
    shape = nil
    when(net foreach(b net->branches foreach(c b->children
      when(c->objType == "shape" shape = c))))
    unless(net && shape
      printf("ERROR: Net '%s' or its copper shape not found\n" netName))
    when(net && shape
      segs = shape->segments
      edges = nil
      for(i 0 length(segs)-2
        edges = cons(list(
          list(car(car(nthelem(i+1 segs)->startEnd)) cadr(car(nthelem(i+1 segs)->startEnd)))
          list(car(car(nthelem(i+2 segs)->startEnd)) cadr(car(nthelem(i+2 segs)->startEnd)))
        ) edges))
      edges = cons(list(
        list(car(car(nthelem(length(segs) segs)->startEnd)) cadr(car(nthelem(length(segs) segs)->startEnd)))
        list(car(car(car(segs)->startEnd)) cadr(car(car(segs)->startEnd)))
      ) edges)

      y_min = 100000  y_max = -100000
      foreach(e edges
        y1 = cadr(car(e))  y2 = cadr(cadr(e))
        when(y1 < y_min y_min = y1) when(y2 < y_min y_min = y2)
        when(y1 > y_max y_max = y1) when(y2 > y_max y_max = y2))

      step = (y_max - y_min) / (nSlices - 1.0)
      slices = nil  scan_y = y_min
      while(scan_y <= y_max + step*0.1
        xs = nil
        foreach(e2 edges
          x1 = car(car(e2))  y1 = cadr(car(e2))
          x2 = car(cadr(e2))  y2 = cadr(cadr(e2))
          when((y1 <= scan_y && y2 > scan_y) || (y2 <= scan_y && y1 > scan_y)
            xs = cons(x1 + (scan_y - y1)*(x2 - x1)/(y2 - y1) xs)))
        xs = sort(xs 'lessp)
        j = 0  width = 0.0
        while(j+1 < length(xs)
          width = width + nthelem(j+2 xs) - nthelem(j+1 xs)
          j = j+2)
        slices = cons(list(round(scan_y) round(width)) slices)
        scan_y = scan_y + step)
      slices = sortcar(slices 'lessp)

      narrow = nil  total = length(slices)
      for(i 0 total-1
        width = cadr(nthelem(i+1 slices))
        prev_w = if(i > 0 cadr(nthelem(i slices)) 999)
        next_w = if(i+1 < total cadr(nthelem(i+2 slices)) 999)
        when(width < threshold &&
             (prev_w < threshold*1.8 || next_w < threshold*1.8)
          narrow = cons(nthelem(i+1 slices) narrow)))
      narrow = sortcar(narrow 'lessp)

      when(draw && narrow
        merged = nil  rs = nil  re = nil  rw = 999
        foreach(bn narrow
          y_curr = car(bn)  w_curr = cadr(bn)
          if(null(rs) then
            rs = y_curr  re = y_curr  rw = w_curr
          else when(y_curr - re < step*2.0
            re = y_curr
            when(w_curr < rw rw = w_curr)
          else
            merged = cons(list(rs re rw) merged)
            rs = y_curr  re = y_curr  rw = w_curr)))
        when(rs merged = cons(list(rs re rw) merged))

        foreach(m merged
          rs = car(m)  re = cadr(m)  rw = caddr(m)
          scan_y = (rs + re) / 2.0
          xs = nil
          foreach(e2 edges
            x1 = car(car(e2))  y1 = cadr(car(e2))
            x2 = car(cadr(e2))  y2 = cadr(cadr(e2))
            when((y1 <= scan_y && y2 > scan_y) || (y2 <= scan_y && y1 > scan_y)
              xs = cons(x1 + (scan_y - y1)*(x2 - x1)/(y2 - y1) xs)))
          xs = sort(xs 'lessp)
          when(length(xs) >= 2
            axlDBCreateRectangle(
              list(car(xs):(rs-10) nthelem(length(xs) xs):(re+10))
              t "BOARD GEOMETRY/SILKSCREEN_TOP" nil nil)))
        axlUIWRedraw(nil))

      sprintf(nil "Net:%s Slices:%d Y:[%d,%d] Regions:%d"
        netName nSlices round(y_min) round(y_max) length(narrow)))))

axlCmdRegister("ai_bottleneck" 'ai_bottleneck ?cmdType "general")
printf("bottleneck.il loaded. ai_bottleneck(NET slices threshold draw)\n")
