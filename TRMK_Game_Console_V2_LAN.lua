--[[
======================================================================
 TRMK GAME CONSOLE - V2 LAN
 CC:Tweaked / ComputerCraft
----------------------------------------------------------------------
 5 jeux integres + vrai multiplayer LAN :
   1. SNAKE       - Solo / Duel 2 joueurs
   2. PONG        - Solo vs IA / Duel 2 joueurs
   3. TETRIS      - Solo / Versus 2 joueurs avec lignes garbage
   4. 2048        - Solo / Race 2 joueurs
   5. MINESWEEPER - Solo / Race 2 joueurs sur grille identique

 Pense pour un Advanced Computer (51x19 recommande).
 Solo local + multiplayer LAN : un ordinateur par joueur.
======================================================================
]]

local SAVE_FILE = ".trmk_game_console_save.json"
local MIN_W, MIN_H = 45, 18

local theme = {
    bg=colors.black, panel=colors.gray, text=colors.white,
    dim=colors.lightGray, accent=colors.cyan, accent2=colors.orange,
    good=colors.lime, bad=colors.red, yellow=colors.yellow,
    blue=colors.blue, magenta=colors.magenta,
}

local save = {
    totalPlays=0,
    scores={snake=0,pong=0,tetris=0,game2048=0,minesweeper=999999},
}

local function loadSave()
    if not fs.exists(SAVE_FILE) then return end
    local f=fs.open(SAVE_FILE,"r")
    if not f then return end
    local raw=f.readAll(); f.close()
    local ok,data=pcall(textutils.unserializeJSON,raw)
    if ok and type(data)=="table" then
        if type(data.totalPlays)=="number" then save.totalPlays=data.totalPlays end
        if type(data.scores)=="table" then
            for k,v in pairs(data.scores) do save.scores[k]=v end
        end
    end
end

local function saveData()
    local f=fs.open(SAVE_FILE,"w")
    if not f then return end
    f.write(textutils.serializeJSON(save)); f.close()
end

loadSave()

local function size() return term.getSize() end

local function cls(bg)
    term.setBackgroundColor(bg or theme.bg)
    term.setTextColor(theme.text)
    term.clear(); term.setCursorPos(1,1)
end

local function writeAt(x,y,text,fg,bg)
    local w,h=size()
    if y<1 or y>h then return end
    text=tostring(text or "")
    if x<1 then text=text:sub(2-x); x=1 end
    if x>w then return end
    if #text>w-x+1 then text=text:sub(1,w-x+1) end
    term.setCursorPos(x,y)
    term.setTextColor(fg or theme.text)
    term.setBackgroundColor(bg or theme.bg)
    term.write(text)
end

local function fill(x1,y1,x2,y2,bg,char)
    local w,h=size()
    x1=math.max(1,x1); y1=math.max(1,y1)
    x2=math.min(w,x2); y2=math.min(h,y2)
    if x2<x1 or y2<y1 then return end
    char=char or " "
    term.setBackgroundColor(bg or theme.bg)
    for y=y1,y2 do
        term.setCursorPos(x1,y)
        term.write(string.rep(char,x2-x1+1))
    end
end

local function centerText(y,text,fg,bg)
    local w=size()
    writeAt(math.floor((w-#text)/2)+1,y,text,fg,bg)
end

local function trunc(text,width)
    text=tostring(text or "")
    if #text<=width then return text end
    if width<=3 then return text:sub(1,width) end
    return text:sub(1,width-3).."..."
end

local function box(x1,y1,x2,y2,title,fg,bg)
    fg=fg or theme.text; bg=bg or theme.bg
    if x2-x1<2 or y2-y1<2 then return end
    writeAt(x1,y1,"+"..string.rep("-",x2-x1-1).."+",fg,bg)
    for y=y1+1,y2-1 do writeAt(x1,y,"|",fg,bg); writeAt(x2,y,"|",fg,bg) end
    writeAt(x1,y2,"+"..string.rep("-",x2-x1-1).."+",fg,bg)
    if title then writeAt(x1+2,y1," "..trunc(title,x2-x1-3).." ",fg,bg) end
end

local function button(x1,y,x2,label,active,color)
    local bg=active and (color or theme.accent) or theme.panel
    local fg=active and colors.black or theme.text
    fill(x1,y,x2,y,bg)
    local tx=x1+math.max(0,math.floor((x2-x1+1-#label)/2))
    writeAt(tx,y,label,fg,bg)
end

local function popup(title,lines,footer)
    local w,h=size()
    local pw=math.min(w-4,math.max(32,#title+6))
    for _,l in ipairs(lines or {}) do pw=math.min(w-4,math.max(pw,#l+4)) end
    local ph=math.min(h-2,#lines+5)
    local x1=math.floor((w-pw)/2)+1
    local y1=math.floor((h-ph)/2)+1
    local x2=x1+pw-1; local y2=y1+ph-1
    fill(x1,y1,x2,y2,theme.panel)
    box(x1,y1,x2,y2,title,theme.text,theme.panel)
    local y=y1+2
    for _,l in ipairs(lines or {}) do
        writeAt(x1+2,y,trunc(l,pw-4),theme.text,theme.panel)
        y=y+1; if y>=y2 then break end
    end
    if footer then writeAt(x1+2,y2-1,trunc(footer,pw-4),theme.yellow,theme.panel) end
end

local function waitKey()
    while true do local ev,a=os.pullEvent(); if ev=="key" then return a end end
end

local function ensureTerminal()
    local w,h=size()
    if w>=MIN_W and h>=MIN_H then return true end
    cls(); centerText(3,"TRMK GAME CONSOLE",theme.accent)
    centerText(6,"Terminal trop petit.",theme.bad)
    centerText(8,string.format("Minimum recommande : %dx%d",MIN_W,MIN_H),theme.text)
    centerText(10,string.format("Actuel : %dx%d",w,h),theme.dim)
    centerText(13,"Utilise un Advanced Computer ou un grand Monitor.",theme.yellow)
    centerText(16,"Appuie sur une touche pour quitter.",theme.dim)
    waitKey(); return false
end

local function randChoice(t) return t[math.random(1,#t)] end
math.randomseed(os.epoch("utc") % 2147483647)

local function modeMenu(gameName,soloLabel,versusLabel)
    local sel=1
    local options={soloLabel or "SOLO",versusLabel or "2 JOUEURS","RETOUR"}
    while true do
        cls(); centerText(2,"TRMK GAME CONSOLE",theme.accent); centerText(4,gameName,theme.yellow)
        local w=size(); local bw=math.min(30,w-8); local x1=math.floor((w-bw)/2)+1
        for i,opt in ipairs(options) do button(x1,7+(i-1)*2,x1+bw-1,opt,i==sel) end
        centerText(15,"Up/Down selection   ENTER valider   ESC retour",theme.dim)
        local _,k=os.pullEvent("key")
        if k==keys.up or k==keys.w then sel=sel-1; if sel<1 then sel=#options end
        elseif k==keys.down or k==keys.s then sel=sel+1; if sel>#options then sel=1 end
        elseif k==keys.enter then
            if sel==1 then return "solo" elseif sel==2 then return "versus" else return nil end
        elseif k==keys.escape or k==keys.q then return nil end
    end
end

-- ================================================================
-- SNAKE
-- ================================================================

local function snakeGame(mode)
    local w,h=size(); local x1,y1=2,3; local x2,y2=w-1,h-2
    local gw=x2-x1-1; local gh=y2-y1-1

    local function makeSnake(sx,sy,dx,dy,col,name)
        return {body={{x=sx,y=sy},{x=sx-dx,y=sy-dy},{x=sx-2*dx,y=sy-2*dy}},
            dx=dx,dy=dy,nextDx=dx,nextDy=dy,alive=true,score=0,color=col,name=name}
    end

    local s1=makeSnake(math.floor(gw/4),math.floor(gh/2),1,0,theme.good,"P1")
    local s2=mode=="versus" and makeSnake(math.floor(gw*3/4),math.floor(gh/2),-1,0,theme.accent2,"P2") or nil
    local apple={x=math.floor(gw/2),y=math.floor(gh/2)}
    local speed=0.12

    local function occupied(x,y)
        for _,s in ipairs({s1,s2}) do
            if s then for _,p in ipairs(s.body) do if p.x==x and p.y==y then return true end end end
        end
        return false
    end

    local function spawnApple()
        for _=1,500 do
            local ax,ay=math.random(1,gw),math.random(1,gh)
            if not occupied(ax,ay) then apple.x,apple.y=ax,ay; return end
        end
    end

    local function setDir(s,dx,dy)
        if not s or not s.alive or (dx==-s.dx and dy==-s.dy) then return end
        s.nextDx,s.nextDy=dx,dy
    end

    local function draw()
        cls(); box(x1,y1,x2,y2," SNAKE ")
        writeAt(2,1,"P1 "..s1.score,theme.good)
        if s2 then writeAt(w-10,1,"P2 "..s2.score,theme.accent2)
        else writeAt(w-16,1,"BEST "..tostring(save.scores.snake or 0),theme.yellow) end
        writeAt(x1+apple.x,y1+apple.y,"@",theme.yellow)
        for _,s in ipairs({s1,s2}) do
            if s then for i,p in ipairs(s.body) do writeAt(x1+p.x,y1+p.y,i==1 and "O" or "o",s.color) end end
        end
        if s2 then writeAt(2,h,"P1 WASD     P2 Fleches     ESC quitter",theme.dim)
        else writeAt(2,h,"WASD/Fleches pour jouer     ESC quitter",theme.dim) end
    end

    local function bodyHit(head,snake,ignoreTail)
        if not snake then return false end
        local max=#snake.body-(ignoreTail and 1 or 0)
        for i=1,max do local p=snake.body[i]; if p.x==head.x and p.y==head.y then return true end end
        return false
    end

    local function nextHead(s)
        s.dx,s.dy=s.nextDx,s.nextDy
        return {x=s.body[1].x+s.dx,y=s.body[1].y+s.dy}
    end

    local function tick()
        local h1=s1.alive and nextHead(s1) or nil
        local h2=s2 and s2.alive and nextHead(s2) or nil

        local function wall(head) return head and (head.x<1 or head.x>gw or head.y<1 or head.y>gh) end
        local d1=wall(h1) or (h1 and (bodyHit(h1,s1,true) or bodyHit(h1,s2,true)))
        local d2=wall(h2) or (h2 and (bodyHit(h2,s2,true) or bodyHit(h2,s1,true)))

        if h1 and h2 then
            if h1.x==h2.x and h1.y==h2.y then d1,d2=true,true end
            if h1.x==s2.body[1].x and h1.y==s2.body[1].y and h2.x==s1.body[1].x and h2.y==s1.body[1].y then d1,d2=true,true end
        end

        if d1 then s1.alive=false end
        if s2 and d2 then s2.alive=false end

        local ate=false
        for _,pair in ipairs({{s1,h1},{s2,h2}}) do
            local s,head=pair[1],pair[2]
            if s and s.alive and head then
                table.insert(s.body,1,head)
                if head.x==apple.x and head.y==apple.y then s.score=s.score+1; ate=true
                else table.remove(s.body) end
            end
        end
        if ate then speed=math.max(0.055,speed-0.004); spawnApple() end
    end

    draw(); local timer=os.startTimer(speed)
    while true do
        local ev,a=os.pullEvent()
        if ev=="key" then
            if a==keys.escape or a==keys.q then return end
            if a==keys.w then setDir(s1,0,-1)
            elseif a==keys.s then setDir(s1,0,1)
            elseif a==keys.a then setDir(s1,-1,0)
            elseif a==keys.d then setDir(s1,1,0)
            elseif mode=="solo" and a==keys.up then setDir(s1,0,-1)
            elseif mode=="solo" and a==keys.down then setDir(s1,0,1)
            elseif mode=="solo" and a==keys.left then setDir(s1,-1,0)
            elseif mode=="solo" and a==keys.right then setDir(s1,1,0)
            elseif s2 and a==keys.up then setDir(s2,0,-1)
            elseif s2 and a==keys.down then setDir(s2,0,1)
            elseif s2 and a==keys.left then setDir(s2,-1,0)
            elseif s2 and a==keys.right then setDir(s2,1,0) end
        elseif ev=="timer" and a==timer then
            tick(); draw()
            if mode=="solo" and not s1.alive then
                save.scores.snake=math.max(save.scores.snake or 0,s1.score); saveData()
                popup("GAME OVER",{"Score : "..s1.score,"Meilleur : "..save.scores.snake},"Appuie sur une touche")
                waitKey(); return
            elseif mode=="versus" and ((not s1.alive) or (s2 and not s2.alive)) then
                local result
                if s1.alive and not s2.alive then result="P1 GAGNE"
                elseif s2.alive and not s1.alive then result="P2 GAGNE"
                elseif s1.score>s2.score then result="P1 GAGNE AU SCORE"
                elseif s2.score>s1.score then result="P2 GAGNE AU SCORE" else result="EGALITE" end
                popup("SNAKE DUEL",{result,"P1 : "..s1.score.."   P2 : "..s2.score},"Appuie sur une touche")
                waitKey(); return
            end
            timer=os.startTimer(speed)
        end
    end
end

-- ================================================================
-- PONG
-- ================================================================

local function pongGame(mode)
    local w,h=size(); local x1,y1=2,3; local x2,y2=w-1,h-2
    local py=math.floor((y1+y2)/2); local paddle=4; local target=7
    local p1={y=py,score=0}; local p2={y=py,score=0}
    local ball={x=math.floor((x1+x2)/2),y=py,vx=1,vy=1}

    local function resetBall(dir)
        ball.x=math.floor((x1+x2)/2); ball.y=math.floor((y1+y2)/2)
        ball.vx=dir or (math.random(0,1)==0 and -1 or 1); ball.vy=randChoice({-1,1})
    end
    local function clampP(p) p.y=math.max(y1+1,math.min(y2-paddle,p.y)) end
    local function draw()
        cls(); box(x1,y1,x2,y2," PONG ")
        for y=y1+1,y2-1 do if y%2==0 then writeAt(math.floor((x1+x2)/2),y,".",theme.dim) end end
        for i=0,paddle-1 do
            writeAt(x1+1,p1.y+i," ",theme.text,theme.good)
            writeAt(x2-1,p2.y+i," ",theme.text,theme.accent2)
        end
        writeAt(math.floor(ball.x),math.floor(ball.y),"O",theme.yellow)
        centerText(1,string.format("%d      :      %d",p1.score,p2.score),theme.text)
        if mode=="versus" then writeAt(2,h,"P1 W/S     P2 Haut/Bas     Premier a "..target,theme.dim)
        else writeAt(2,h,"W/S ou Haut/Bas     VS IA     Premier a "..target,theme.dim) end
    end

    resetBall(); draw(); local timer=os.startTimer(0.06)
    while true do
        local ev,a=os.pullEvent()
        if ev=="key" then
            if a==keys.escape or a==keys.q then return end
            if a==keys.w or (mode=="solo" and a==keys.up) then p1.y=p1.y-1; clampP(p1)
            elseif a==keys.s or (mode=="solo" and a==keys.down) then p1.y=p1.y+1; clampP(p1)
            elseif mode=="versus" and a==keys.up then p2.y=p2.y-1; clampP(p2)
            elseif mode=="versus" and a==keys.down then p2.y=p2.y+1; clampP(p2) end
            draw()
        elseif ev=="timer" and a==timer then
            if mode=="solo" then
                local c=p2.y+(paddle-1)/2
                if ball.y<c-0.4 then p2.y=p2.y-1 elseif ball.y>c+0.4 then p2.y=p2.y+1 end
                clampP(p2)
            end
            local nx,ny=ball.x+ball.vx,ball.y+ball.vy
            if ny<=y1+1 then ny=y1+1; ball.vy=math.abs(ball.vy)
            elseif ny>=y2-1 then ny=y2-1; ball.vy=-math.abs(ball.vy) end
            if ball.vx<0 and nx<=x1+2 and ny>=p1.y and ny<=p1.y+paddle-1 then
                nx=x1+2; ball.vx=math.abs(ball.vx)
                ball.vy=math.max(-1.4,math.min(1.4,ball.vy+((ny-(p1.y+(paddle-1)/2))/paddle)*0.8))
            elseif ball.vx>0 and nx>=x2-2 and ny>=p2.y and ny<=p2.y+paddle-1 then
                nx=x2-2; ball.vx=-math.abs(ball.vx)
                ball.vy=math.max(-1.4,math.min(1.4,ball.vy+((ny-(p2.y+(paddle-1)/2))/paddle)*0.8))
            end
            ball.x,ball.y=nx,ny
            if ball.x<x1+1 then p2.score=p2.score+1; resetBall(1)
            elseif ball.x>x2-1 then p1.score=p1.score+1; resetBall(-1) end
            draw()
            if p1.score>=target or p2.score>=target then
                local msg=p1.score>p2.score and "P1 GAGNE !" or (mode=="solo" and "L'IA GAGNE" or "P2 GAGNE !")
                if mode=="solo" and p1.score>p2.score then save.scores.pong=(save.scores.pong or 0)+1; saveData() end
                popup("PONG",{msg,string.format("%d - %d",p1.score,p2.score)},"Appuie sur une touche")
                waitKey(); return
            end
            timer=os.startTimer(0.06)
        end
    end
end

-- ================================================================
-- TETRIS
-- ================================================================

local TETROMINOS={
    I={color=colors.cyan,rots={{{0,0},{1,0},{2,0},{3,0}},{{1,-1},{1,0},{1,1},{1,2}}}},
    O={color=colors.yellow,rots={{{0,0},{1,0},{0,1},{1,1}}}},
    T={color=colors.purple,rots={{{-1,0},{0,0},{1,0},{0,1}},{{0,-1},{0,0},{1,0},{0,1}},{{-1,0},{0,0},{1,0},{0,-1}},{{0,-1},{0,0},{-1,0},{0,1}}}},
    S={color=colors.lime,rots={{{0,0},{1,0},{-1,1},{0,1}},{{0,-1},{0,0},{1,0},{1,1}}}},
    Z={color=colors.red,rots={{{-1,0},{0,0},{0,1},{1,1}},{{1,-1},{0,0},{1,0},{0,1}}}},
    J={color=colors.blue,rots={{{-1,0},{0,0},{1,0},{-1,1}},{{0,-1},{0,0},{0,1},{1,1}},{{1,-1},{-1,0},{0,0},{1,0}},{{-1,-1},{0,-1},{0,0},{0,1}}}},
    L={color=colors.orange,rots={{{-1,0},{0,0},{1,0},{1,1}},{{0,-1},{0,0},{0,1},{1,-1}},{{-1,-1},{-1,0},{0,0},{1,0}},{{-1,1},{0,-1},{0,0},{0,1}}}},
}
local PIECE_NAMES={"I","O","T","S","Z","J","L"}

local function newTetrisPlayer(name,color)
    local p={name=name,color=color,w=10,h=13,grid={},score=0,lines=0,level=1,dead=false,piece=nil,next=nil}
    for y=1,p.h do p.grid[y]={}; for x=1,p.w do p.grid[y][x]=0 end end
    return p
end

local function pieceCells(piece)
    local def=TETROMINOS[piece.kind]; local rots=def.rots; local r=((piece.rot-1)%#rots)+1
    local cells={}
    for _,c in ipairs(rots[r]) do table.insert(cells,{x=piece.x+c[1],y=piece.y+c[2]}) end
    return cells,def.color
end

local function validPiece(p,piece)
    local cells=pieceCells(piece)
    for _,c in ipairs(cells) do
        if c.x<1 or c.x>p.w or c.y>p.h then return false end
        if c.y>=1 and p.grid[c.y][c.x]~=0 then return false end
    end
    return true
end

local function spawnPiece(p)
    local kind=p.next or randChoice(PIECE_NAMES); p.next=randChoice(PIECE_NAMES)
    p.piece={kind=kind,rot=1,x=5,y=1}
    if not validPiece(p,p.piece) then p.dead=true end
end

local function clearLines(p)
    local cleared=0; local y=p.h
    while y>=1 do
        local full=true
        for x=1,p.w do if p.grid[y][x]==0 then full=false; break end end
        if full then
            table.remove(p.grid,y); local row={}; for x=1,p.w do row[x]=0 end
            table.insert(p.grid,1,row); cleared=cleared+1
        else y=y-1 end
    end
    if cleared>0 then
        local pts={0,100,300,500,800}
        p.score=p.score+(pts[cleared+1] or cleared*300)*p.level
        p.lines=p.lines+cleared; p.level=1+math.floor(p.lines/8)
    end
    return cleared
end

local function lockPiece(p)
    local cells,col=pieceCells(p.piece)
    for _,c in ipairs(cells) do if c.y>=1 and c.y<=p.h then p.grid[c.y][c.x]=col end end
    local cleared=clearLines(p); spawnPiece(p); return cleared
end

local function movePiece(p,dx,dy)
    if p.dead then return false end
    local np={kind=p.piece.kind,rot=p.piece.rot,x=p.piece.x+dx,y=p.piece.y+dy}
    if validPiece(p,np) then p.piece=np; return true end
    return false
end

local function rotatePiece(p)
    if p.dead then return end
    local np={kind=p.piece.kind,rot=p.piece.rot+1,x=p.piece.x,y=p.piece.y}
    for _,kx in ipairs({0,-1,1,-2,2}) do np.x=p.piece.x+kx; if validPiece(p,np) then p.piece=np; return end end
end

local function hardDrop(p)
    if p.dead then return 0 end
    local n=0; while movePiece(p,0,1) do n=n+1 end
    p.score=p.score+n*2; return lockPiece(p)
end

local function addGarbage(p,count)
    if p.dead or count<=0 then return end
    for _=1,count do
        table.remove(p.grid,1); local hole=math.random(1,p.w); local row={}
        for x=1,p.w do row[x]=(x==hole) and 0 or colors.gray end
        table.insert(p.grid,row)
    end
    if p.piece and not validPiece(p,p.piece) then p.dead=true end
end

local function tetrisGame(mode)
    local w,h=size(); local p1=newTetrisPlayer("P1",theme.good)
    local p2=mode=="versus" and newTetrisPlayer("P2",theme.accent2) or nil
    p1.next=randChoice(PIECE_NAMES); spawnPiece(p1)
    if p2 then p2.next=randChoice(PIECE_NAMES); spawnPiece(p2) end
    local boardTop=3; local boardW=12
    local p1x=mode=="versus" and 4 or math.floor((w-boardW)/2)+1
    local p2x=p2 and (w-boardW-3) or nil

    local function drawBoard(p,bx)
        box(bx,boardTop,bx+boardW-1,boardTop+p.h+1,p.name,p.color)
        for y=1,p.h do for x=1,p.w do
            local c=p.grid[y][x]; writeAt(bx+x,boardTop+y," ",colors.white,c~=0 and c or colors.black)
        end end
        if p.piece and not p.dead then
            local cells,col=pieceCells(p.piece)
            for _,c in ipairs(cells) do if c.y>=1 and c.y<=p.h and c.x>=1 and c.x<=p.w then writeAt(bx+c.x,boardTop+c.y," ",colors.white,col) end end
        end
        writeAt(bx,boardTop+p.h+2,trunc("S:"..p.score.." L:"..p.lines,boardW),p.color)
    end

    local function draw()
        cls(); centerText(1,"TETRIS",theme.yellow); drawBoard(p1,p1x); if p2 then drawBoard(p2,p2x) end
        if p2 then writeAt(1,h,"P1 A/D W rot S drop | P2 Fleches | Shift = hard drop",theme.dim)
        else writeAt(2,h,"Fleches bouger/rot/drop   ESPACE hard drop   ESC quitter",theme.dim) end
    end

    local function handleClear(attacker,defender,cleared)
        if mode=="versus" and defender and cleared>=2 then addGarbage(defender,cleared-1) end
    end

    local fall1=os.startTimer(0.45); local fall2=p2 and os.startTimer(0.45) or nil; draw()
    while true do
        local ev,a=os.pullEvent()
        if ev=="key" then
            if a==keys.escape or a==keys.q then return end
            if mode=="solo" then
                if a==keys.left then movePiece(p1,-1,0)
                elseif a==keys.right then movePiece(p1,1,0)
                elseif a==keys.up then rotatePiece(p1)
                elseif a==keys.down then if not movePiece(p1,0,1) then handleClear(p1,nil,lockPiece(p1)) end
                elseif a==keys.space then handleClear(p1,nil,hardDrop(p1)) end
            else
                if a==keys.a then movePiece(p1,-1,0)
                elseif a==keys.d then movePiece(p1,1,0)
                elseif a==keys.w then rotatePiece(p1)
                elseif a==keys.s then if not movePiece(p1,0,1) then handleClear(p1,p2,lockPiece(p1)) end
                elseif a==keys.left then movePiece(p2,-1,0)
                elseif a==keys.right then movePiece(p2,1,0)
                elseif a==keys.up then rotatePiece(p2)
                elseif a==keys.down then if not movePiece(p2,0,1) then handleClear(p2,p1,lockPiece(p2)) end
                elseif a==keys.leftShift then handleClear(p1,p2,hardDrop(p1))
                elseif a==keys.rightShift then handleClear(p2,p1,hardDrop(p2)) end
            end
            draw()
        elseif ev=="timer" then
            if a==fall1 and not p1.dead then
                if not movePiece(p1,0,1) then handleClear(p1,p2,lockPiece(p1)) end
                fall1=os.startTimer(math.max(0.12,0.45-(p1.level-1)*0.035)); draw()
            elseif p2 and a==fall2 and not p2.dead then
                if not movePiece(p2,0,1) then handleClear(p2,p1,lockPiece(p2)) end
                fall2=os.startTimer(math.max(0.12,0.45-(p2.level-1)*0.035)); draw()
            end
        end
        if mode=="solo" and p1.dead then
            save.scores.tetris=math.max(save.scores.tetris or 0,p1.score); saveData()
            popup("TETRIS - GAME OVER",{"Score : "..p1.score,"Lignes : "..p1.lines,"Best : "..save.scores.tetris},"Appuie sur une touche")
            waitKey(); return
        elseif mode=="versus" and (p1.dead or p2.dead) then
            local msg
            if p1.dead and p2.dead then
                if p1.score>p2.score then msg="P1 GAGNE AU SCORE" elseif p2.score>p1.score then msg="P2 GAGNE AU SCORE" else msg="EGALITE" end
            elseif p1.dead then msg="P2 GAGNE" else msg="P1 GAGNE" end
            popup("TETRIS VERSUS",{msg,"P1 "..p1.score.." | P2 "..p2.score},"Appuie sur une touche")
            waitKey(); return
        end
    end
end

-- ================================================================
-- 2048
-- ================================================================

local function new2048Board()
    local b={}; for y=1,4 do b[y]={0,0,0,0} end; return b
end
local function cloneGrid(g)
    local n={}; for y=1,#g do n[y]={}; for x=1,#g[y] do n[y][x]=g[y][x] end end; return n
end
local function gridEqual(a,b)
    for y=1,4 do for x=1,4 do if a[y][x]~=b[y][x] then return false end end end; return true
end
local function add2048Tile(b)
    local empty={}; for y=1,4 do for x=1,4 do if b[y][x]==0 then table.insert(empty,{x=x,y=y}) end end end
    if #empty==0 then return false end
    local p=randChoice(empty); b[p.y][p.x]=(math.random()<0.9) and 2 or 4; return true
end
local function collapseLine(line)
    local vals={}; for _,v in ipairs(line) do if v~=0 then table.insert(vals,v) end end
    local out={}; local gain=0; local i=1
    while i<=#vals do
        if i<#vals and vals[i]==vals[i+1] then local nv=vals[i]*2; table.insert(out,nv); gain=gain+nv; i=i+2
        else table.insert(out,vals[i]); i=i+1 end
    end
    while #out<4 do table.insert(out,0) end
    return out,gain
end
local function move2048(b,dir)
    local before=cloneGrid(b); local gain=0
    local function getLine(i)
        local line={}
        if dir=="left" then for x=1,4 do line[x]=b[i][x] end
        elseif dir=="right" then for x=1,4 do line[x]=b[i][5-x] end
        elseif dir=="up" then for y=1,4 do line[y]=b[y][i] end
        else for y=1,4 do line[y]=b[5-y][i] end end
        return line
    end
    local function setLine(i,line)
        if dir=="left" then for x=1,4 do b[i][x]=line[x] end
        elseif dir=="right" then for x=1,4 do b[i][5-x]=line[x] end
        elseif dir=="up" then for y=1,4 do b[y][i]=line[y] end
        else for y=1,4 do b[5-y][i]=line[y] end end
    end
    for i=1,4 do local line=getLine(i); local out,g=collapseLine(line); setLine(i,out); gain=gain+g end
    local changed=not gridEqual(before,b); if changed then add2048Tile(b) end
    return changed,gain
end
local function can2048Move(b)
    for y=1,4 do for x=1,4 do
        if b[y][x]==0 then return true end
        if x<4 and b[y][x]==b[y][x+1] then return true end
        if y<4 and b[y][x]==b[y+1][x] then return true end
    end end
    return false
end
local function maxTile(b)
    local m=0; for y=1,4 do for x=1,4 do m=math.max(m,b[y][x]) end end; return m
end
local tileColors={[0]=colors.gray,[2]=colors.white,[4]=colors.lightGray,[8]=colors.orange,[16]=colors.yellow,[32]=colors.red,[64]=colors.pink,[128]=colors.magenta,[256]=colors.purple,[512]=colors.blue,[1024]=colors.cyan,[2048]=colors.lime}
local function draw2048Board(b,bx,by,title,score,col)
    local cellW=5; box(bx,by,bx+4*cellW+1,by+9,title,col)
    for y=1,4 do for x=1,4 do
        local v=b[y][x]; local bg=tileColors[v] or colors.green; local sx=bx+1+(x-1)*cellW; local sy=by+1+(y-1)*2
        fill(sx,sy,sx+cellW-1,sy+1,bg)
        if v~=0 then local s=tostring(v); writeAt(sx+math.floor((cellW-#s)/2),sy,s,colors.black,bg) end
    end end
    writeAt(bx,by+10,"Score "..score,col)
end

local function game2048(mode)
    local w,h=size(); local b1=new2048Board(); local b2=mode=="versus" and new2048Board() or nil
    add2048Tile(b1); add2048Tile(b1); if b2 then add2048Tile(b2); add2048Tile(b2) end
    local s1,s2=0,0; local bx1=mode=="versus" and 2 or math.floor((w-22)/2)+1; local bx2=b2 and (w-23) or nil
    local function draw()
        cls(); centerText(1,"2048",theme.yellow); draw2048Board(b1,bx1,3,"P1",s1,theme.good); if b2 then draw2048Board(b2,bx2,3,"P2",s2,theme.accent2) end
        if b2 then writeAt(2,h,"P1 WASD    P2 Fleches    Premier a 2048 / dernier vivant",theme.dim)
        else writeAt(2,h,"WASD ou Fleches   Fusionne les tuiles jusqu'a 2048",theme.dim) end
    end
    local function doMove(player,dir)
        if player==1 then local ch,g=move2048(b1,dir); if ch then s1=s1+g end
        else local ch,g=move2048(b2,dir); if ch then s2=s2+g end end
    end
    draw()
    while true do
        local _,k=os.pullEvent("key"); if k==keys.escape or k==keys.q then return end
        if mode=="solo" then
            if k==keys.w or k==keys.up then doMove(1,"up") elseif k==keys.s or k==keys.down then doMove(1,"down")
            elseif k==keys.a or k==keys.left then doMove(1,"left") elseif k==keys.d or k==keys.right then doMove(1,"right") end
        else
            if k==keys.w then doMove(1,"up") elseif k==keys.s then doMove(1,"down") elseif k==keys.a then doMove(1,"left") elseif k==keys.d then doMove(1,"right")
            elseif k==keys.up then doMove(2,"up") elseif k==keys.down then doMove(2,"down") elseif k==keys.left then doMove(2,"left") elseif k==keys.right then doMove(2,"right") end
        end
        draw()
        if mode=="solo" then
            if maxTile(b1)>=2048 then
                save.scores.game2048=math.max(save.scores.game2048 or 0,s1); saveData()
                popup("2048 !",{"Tu as atteint 2048 !","Score : "..s1},"Appuie sur une touche"); waitKey(); return
            elseif not can2048Move(b1) then
                save.scores.game2048=math.max(save.scores.game2048 or 0,s1); saveData()
                popup("GAME OVER",{"Score : "..s1,"Max tile : "..maxTile(b1)},"Appuie sur une touche"); waitKey(); return
            end
        else
            local win1,win2=maxTile(b1)>=2048,maxTile(b2)>=2048; local dead1,dead2=not can2048Move(b1),not can2048Move(b2)
            if win1 or win2 or dead1 or dead2 then
                local msg
                if win1 and not win2 then msg="P1 ATTEINT 2048" elseif win2 and not win1 then msg="P2 ATTEINT 2048"
                elseif dead1 and not dead2 then msg="P2 GAGNE" elseif dead2 and not dead1 then msg="P1 GAGNE"
                elseif s1>s2 then msg="P1 GAGNE AU SCORE" elseif s2>s1 then msg="P2 GAGNE AU SCORE" else msg="EGALITE" end
                popup("2048 RACE",{msg,"P1 "..s1.." | P2 "..s2},"Appuie sur une touche"); waitKey(); return
            end
        end
    end
end

-- ================================================================
-- MINESWEEPER
-- ================================================================

local function makeMineLayout(w,h,mineCount)
    local mines={}; for y=1,h do mines[y]={}; for x=1,w do mines[y][x]=false end end
    local placed=0
    while placed<mineCount do local x,y=math.random(1,w),math.random(1,h); if not mines[y][x] then mines[y][x]=true; placed=placed+1 end end
    return mines
end
local function newMinePlayer(w,h,mines)
    local p={w=w,h=h,mines=mines,revealed={},flags={},cx=1,cy=1,dead=false,won=false,start=os.clock(),finish=nil}
    for y=1,h do p.revealed[y]={}; p.flags[y]={}; for x=1,w do p.revealed[y][x]=false; p.flags[y][x]=false end end
    return p
end
local function mineCountAround(p,x,y)
    local n=0
    for dy=-1,1 do for dx=-1,1 do if not(dx==0 and dy==0) then
        local xx,yy=x+dx,y+dy; if xx>=1 and xx<=p.w and yy>=1 and yy<=p.h and p.mines[yy][xx] then n=n+1 end
    end end end
    return n
end
local function revealMineCell(p,x,y)
    if p.dead or p.won or p.flags[y][x] or p.revealed[y][x] then return end
    if p.mines[y][x] then p.revealed[y][x]=true; p.dead=true; p.finish=os.clock(); return end
    local queue={{x=x,y=y}}; local qi=1
    while qi<=#queue do
        local c=queue[qi]; qi=qi+1
        if c.x>=1 and c.x<=p.w and c.y>=1 and c.y<=p.h and not p.revealed[c.y][c.x] and not p.flags[c.y][c.x] then
            p.revealed[c.y][c.x]=true
            if mineCountAround(p,c.x,c.y)==0 then
                for dy=-1,1 do for dx=-1,1 do if not(dx==0 and dy==0) then table.insert(queue,{x=c.x+dx,y=c.y+dy}) end end end
            end
        end
    end
end
local function checkMineWin(p)
    if p.dead then return false end
    for y=1,p.h do for x=1,p.w do if not p.mines[y][x] and not p.revealed[y][x] then return false end end end
    if not p.won then p.won=true; p.finish=os.clock() end
    return true
end
local mineNumColors={[1]=colors.blue,[2]=colors.green,[3]=colors.red,[4]=colors.purple,[5]=colors.orange,[6]=colors.cyan,[7]=colors.black,[8]=colors.gray}
local function drawMineBoard(p,bx,by,title,col)
    box(bx,by,bx+p.w+1,by+p.h+1,title,col)
    for y=1,p.h do for x=1,p.w do
        local ch=" "; local fg=colors.white; local bg=colors.gray
        if p.revealed[y][x] then
            bg=colors.lightGray
            if p.mines[y][x] then ch="*"; fg=colors.red else local n=mineCountAround(p,x,y); if n>0 then ch=tostring(n); fg=mineNumColors[n] or colors.black end end
        elseif p.flags[y][x] then ch="F"; fg=colors.yellow end
        if x==p.cx and y==p.cy and not p.dead and not p.won then bg=colors.cyan end
        writeAt(bx+x,by+y,ch,fg,bg)
    end end
end

local function minesweeperGame(mode)
    local gw,gh,mineCount=12,10,18; local layout=makeMineLayout(gw,gh,mineCount)
    local p1=newMinePlayer(gw,gh,layout); local p2=mode=="versus" and newMinePlayer(gw,gh,layout) or nil
    local w,h=size(); local bx1=mode=="versus" and 3 or math.floor((w-gw-2)/2)+1; local bx2=p2 and (w-gw-4) or nil
    local function draw()
        cls(); centerText(1,"MINESWEEPER",theme.yellow); drawMineBoard(p1,bx1,3,"P1",theme.good); if p2 then drawMineBoard(p2,bx2,3,"P2",theme.accent2) end
        if p2 then
            writeAt(1,h-1,"P1 WASD + E reveal + R flag | P2 Fleches + ENTER reveal + / flag",theme.dim)
            writeAt(1,h,"Meme grille pour les 2 joueurs - le plus rapide gagne",theme.dim)
        else
            writeAt(2,h-1,"Fleches/WASD bouger   ENTER reveal   F flag",theme.dim)
            writeAt(2,h,"Mines : "..mineCount.."     ESC quitter",theme.dim)
        end
    end
    local function moveCursor(p,dx,dy) if not p.dead and not p.won then p.cx=math.max(1,math.min(p.w,p.cx+dx)); p.cy=math.max(1,math.min(p.h,p.cy+dy)) end end
    local function reveal(p) revealMineCell(p,p.cx,p.cy); checkMineWin(p) end
    local function flag(p) if not p.dead and not p.won and not p.revealed[p.cy][p.cx] then p.flags[p.cy][p.cx]=not p.flags[p.cy][p.cx] end end
    draw()
    while true do
        local _,a=os.pullEvent("key"); if a==keys.escape or a==keys.q then return end
        if mode=="solo" then
            if a==keys.up or a==keys.w then moveCursor(p1,0,-1) elseif a==keys.down or a==keys.s then moveCursor(p1,0,1)
            elseif a==keys.left or a==keys.a then moveCursor(p1,-1,0) elseif a==keys.right or a==keys.d then moveCursor(p1,1,0)
            elseif a==keys.enter or a==keys.e then reveal(p1) elseif a==keys.f or a==keys.r then flag(p1) end
        else
            if a==keys.w then moveCursor(p1,0,-1) elseif a==keys.s then moveCursor(p1,0,1) elseif a==keys.a then moveCursor(p1,-1,0) elseif a==keys.d then moveCursor(p1,1,0)
            elseif a==keys.e then reveal(p1) elseif a==keys.r then flag(p1)
            elseif a==keys.up then moveCursor(p2,0,-1) elseif a==keys.down then moveCursor(p2,0,1) elseif a==keys.left then moveCursor(p2,-1,0) elseif a==keys.right then moveCursor(p2,1,0)
            elseif a==keys.enter then reveal(p2) elseif a==keys.slash then flag(p2) end
        end
        draw()
        if mode=="solo" then
            if p1.dead then popup("BOOM !",{"Tu as touche une mine."},"Appuie sur une touche"); waitKey(); return
            elseif p1.won then
                local t=p1.finish-p1.start; if (save.scores.minesweeper or 999999)>t then save.scores.minesweeper=t; saveData() end
                popup("VICTOIRE !",{string.format("Temps : %.1fs",t),string.format("Best : %.1fs",save.scores.minesweeper)},"Appuie sur une touche"); waitKey(); return
            end
        else
            if p1.won or p2.won or (p1.dead and p2.dead) then
                local msg
                if p1.won and not p2.won then msg="P1 GAGNE" elseif p2.won and not p1.won then msg="P2 GAGNE"
                elseif p1.won and p2.won then msg=(p1.finish<p2.finish) and "P1 GAGNE" or "P2 GAGNE" else msg="DOUBLE BOOM - EGALITE" end
                popup("MINESWEEPER RACE",{msg},"Appuie sur une touche"); waitKey(); return
            end
        end
    end
end


-- ================================================================
-- V2 LAN MULTIPLAYER - ONE COMPUTER PER PLAYER
-- ================================================================

local NET_DISC = "trmk.games.v2.discovery"
local NET_PLAY = "trmk.games.v2.play"
local SIDES = {"top","bottom","left","right","front","back"}

local function computerName()
    return os.getComputerLabel() or ("PC-"..os.getComputerID())
end

local function openNetwork()
    local opened = 0
    for _,side in ipairs(SIDES) do
        if peripheral.hasType(side,"modem") then
            if not rednet.isOpen(side) then pcall(rednet.open,side) end
            if rednet.isOpen(side) then opened = opened + 1 end
        end
    end
    return opened
end

local function networkRequired()
    if openNetwork() > 0 then return true end
    popup("MODEM REQUIS",{
        "Aucun modem local detecte.",
        "",
        "Branche un Wired Modem au PC",
        "ou utilise un Wireless Modem.",
        "Les deux PC doivent partager le meme reseau."
    },"Appuie sur une touche")
    waitKey()
    return false
end

local function sessionSend(session,msg)
    msg.session = session.session
    msg.game = session.game
    rednet.send(session.peer,msg,NET_PLAY)
end

local function matchingPlayMessage(sender,msg,proto,session)
    return proto == NET_PLAY
        and sender == session.peer
        and type(msg) == "table"
        and msg.session == session.session
        and msg.game == session.game
end

local function drawNetworkBanner(title,subtitle)
    cls()
    centerText(2,"TRMK GAME CONSOLE // LAN",theme.accent)
    centerText(4,title,theme.yellow)
    if subtitle then centerText(6,subtitle,theme.dim) end
end

local function hostLobby(gameKey,title)
    if not networkRequired() then return nil end

    local sessionId = tostring(os.getComputerID()).."-"..tostring(math.random(1000,9999))
    local peer = nil
    local peerName = nil
    local advertiseTimer = os.startTimer(0.05)

    while true do
        drawNetworkBanner(title,"HOST LOBBY")
        centerText(8,"Lobby "..sessionId,theme.text)

        if peer then
            centerText(10,"P2 CONNECTE : "..trunc(peerName or ("PC-"..peer),28),theme.good)
            centerText(12,"ENTER pour lancer la partie",theme.yellow)
        else
            centerText(10,"En attente d'un joueur...",theme.dim)
            centerText(12,"L'autre PC : MULTI > JOIN",theme.dim)
        end

        centerText(16,"ESC annuler",theme.dim)

        local ev,a,b,c = os.pullEvent()

        if ev=="timer" and a==advertiseTimer then
            rednet.broadcast({
                type="advertise",
                session=sessionId,
                game=gameKey,
                title=title,
                host=computerName(),
                players=peer and 2 or 1,
            },NET_DISC)
            advertiseTimer=os.startTimer(0.65)

        elseif ev=="rednet_message" and c==NET_DISC and type(b)=="table" then
            if b.type=="discover" and (not b.game or b.game==gameKey) then
                rednet.send(a,{
                    type="advertise",
                    session=sessionId,
                    game=gameKey,
                    title=title,
                    host=computerName(),
                    players=peer and 2 or 1,
                },NET_DISC)

            elseif b.type=="join" and b.session==sessionId then
                if not peer or peer==a then
                    peer=a
                    peerName=tostring(b.name or ("PC-"..a))
                    rednet.send(a,{
                        type="join_accept",
                        session=sessionId,
                        game=gameKey,
                        host=computerName(),
                    },NET_DISC)
                else
                    rednet.send(a,{
                        type="join_reject",
                        session=sessionId,
                        reason="Lobby complet"
                    },NET_DISC)
                end

            elseif b.type=="leave" and b.session==sessionId and a==peer then
                peer=nil
                peerName=nil
            end

        elseif ev=="key" then
            if a==keys.escape or a==keys.q then
                if peer then
                    rednet.send(peer,{type="cancel",session=sessionId,game=gameKey},NET_DISC)
                end
                return nil

            elseif a==keys.enter and peer then
                local seed=math.random(1,2147483000)
                rednet.send(peer,{
                    type="start",
                    session=sessionId,
                    game=gameKey,
                    seed=seed,
                },NET_DISC)

                return {
                    role="host",
                    peer=peer,
                    peerName=peerName,
                    session=sessionId,
                    game=gameKey,
                    seed=seed,
                }
            end
        end
    end
end

local function scanLobbies(gameKey,title)
    if not networkRequired() then return {} end

    drawNetworkBanner(title,"Recherche des parties...")
    centerText(10,"Scanning LAN...",theme.dim)

    local found={}
    local bySession={}
    rednet.broadcast({type="discover",game=gameKey},NET_DISC)

    local timer=os.startTimer(1.8)
    while true do
        local ev,a,b,c=os.pullEvent()
        if ev=="timer" and a==timer then break end
        if ev=="rednet_message" and c==NET_DISC and type(b)=="table"
            and b.type=="advertise" and b.game==gameKey and (b.players or 1)<2 then
            if not bySession[b.session] then
                local row={
                    hostId=a,
                    session=b.session,
                    host=tostring(b.host or ("PC-"..a)),
                    title=tostring(b.title or title),
                }
                bySession[b.session]=row
                table.insert(found,row)
            end
        end
    end
    return found
end

local function joinLobby(gameKey,title)
    while true do
        local lobbies=scanLobbies(gameKey,title)
        local sel=1

        while true do
            drawNetworkBanner(title,"JOIN LOBBY")

            if #lobbies==0 then
                centerText(9,"Aucune partie trouvee.",theme.bad)
                centerText(11,"R = rescanner",theme.yellow)
            else
                local y=8
                for i,lobby in ipairs(lobbies) do
                    local active=i==sel
                    local label=trunc(lobby.host.."  ["..lobby.session.."]",34)
                    local w=size()
                    button(math.max(3,math.floor((w-38)/2)),y,
                        math.min(w-2,math.floor((w-38)/2)+37),
                        label,active,theme.accent2)
                    y=y+2
                end
            end

            centerText(17,"ENTER rejoindre   R refresh   ESC retour",theme.dim)
            local _,k=os.pullEvent("key")

            if k==keys.escape or k==keys.q then return nil
            elseif k==keys.r then break
            elseif #lobbies>0 and (k==keys.up or k==keys.w) then
                sel=sel-1 if sel<1 then sel=#lobbies end
            elseif #lobbies>0 and (k==keys.down or k==keys.s) then
                sel=sel+1 if sel>#lobbies then sel=1 end
            elseif #lobbies>0 and k==keys.enter then
                local lobby=lobbies[sel]
                rednet.send(lobby.hostId,{
                    type="join",
                    session=lobby.session,
                    game=gameKey,
                    name=computerName(),
                },NET_DISC)

                drawNetworkBanner(title,"Connexion a "..lobby.host)
                centerText(10,"Handshake...",theme.dim)

                local timeout=os.startTimer(5)
                local accepted=false

                while true do
                    local ev,a,b,c=os.pullEvent()
                    if ev=="timer" and a==timeout then
                        popup("CONNEXION",{"Le host ne repond pas."},"Appuie sur une touche")
                        waitKey()
                        break
                    elseif ev=="rednet_message" and a==lobby.hostId and c==NET_DISC and type(b)=="table"
                        and b.session==lobby.session then

                        if b.type=="join_accept" then
                            accepted=true
                            break
                        elseif b.type=="join_reject" then
                            popup("REFUSE",{tostring(b.reason or "Lobby refuse")},"Appuie sur une touche")
                            waitKey()
                            break
                        end
                    elseif ev=="key" and (a==keys.escape or a==keys.q) then
                        rednet.send(lobby.hostId,{type="leave",session=lobby.session,game=gameKey},NET_DISC)
                        return nil
                    end
                end

                if accepted then
                    while true do
                        drawNetworkBanner(title,"CONNECTE A "..lobby.host)
                        centerText(9,"P2 READY",theme.good)
                        centerText(11,"Le host doit lancer la partie.",theme.dim)
                        centerText(16,"ESC quitter le lobby",theme.dim)

                        local ev,a,b,c=os.pullEvent()
                        if ev=="rednet_message" and a==lobby.hostId and c==NET_DISC and type(b)=="table"
                            and b.session==lobby.session then
                            if b.type=="start" then
                                return {
                                    role="client",
                                    peer=lobby.hostId,
                                    peerName=lobby.host,
                                    session=lobby.session,
                                    game=gameKey,
                                    seed=b.seed,
                                }
                            elseif b.type=="cancel" then
                                popup("LOBBY FERME",{"Le host a ferme la partie."},"Appuie sur une touche")
                                waitKey()
                                return nil
                            end
                        elseif ev=="key" and (a==keys.escape or a==keys.q) then
                            rednet.send(lobby.hostId,{type="leave",session=lobby.session,game=gameKey},NET_DISC)
                            return nil
                        end
                    end
                end
            end
        end
    end
end

local function multiplayerMenu(gameKey,title)
    local sel=1
    local opts={"HOST GAME","JOIN GAME","RETOUR"}
    while true do
        drawNetworkBanner(title,"MULTIPLAYER LAN")
        local w=size()
        local bw=30
        local x=math.floor((w-bw)/2)+1
        for i,opt in ipairs(opts) do button(x,8+(i-1)*2,x+bw-1,opt,i==sel,theme.accent2) end
        centerText(16,"1 PC par joueur // modem filaire ou sans fil",theme.dim)
        local _,k=os.pullEvent("key")
        if k==keys.up or k==keys.w then sel=sel-1 if sel<1 then sel=#opts end
        elseif k==keys.down or k==keys.s then sel=sel+1 if sel>#opts then sel=1 end
        elseif k==keys.escape or k==keys.q then return nil
        elseif k==keys.enter then
            if sel==1 then return hostLobby(gameKey,title)
            elseif sel==2 then return joinLobby(gameKey,title)
            else return nil end
        end
    end
end

local function clientGameLoop(session,render,keyMapper)
    local snapshot=nil

    drawNetworkBanner("MULTIPLAYER","Synchronisation avec le host...")
    centerText(10,"Waiting state...",theme.dim)

    while true do
        local ev,a,b,c=os.pullEvent()

        if ev=="key" then
            if a==keys.escape or a==keys.q then
                sessionSend(session,{type="quit"})
                return
            end

            local action=keyMapper(a)
            if action then sessionSend(session,{type="input",action=action}) end

        elseif ev=="rednet_message" and matchingPlayMessage(a,b,c,session) then
            if b.type=="state" then
                snapshot=b.state
                render(snapshot,2)

            elseif b.type=="gameover" then
                if b.state then
                    snapshot=b.state
                    render(snapshot,2)
                end
                popup("MATCH TERMINE",{tostring(b.reason or "Game over")},"Appuie sur une touche")
                waitKey()
                return

            elseif b.type=="peer_quit" then
                popup("PARTIE TERMINEE",{"Le host a quitte."},"Appuie sur une touche")
                waitKey()
                return
            end
        end
    end
end

local function netKeyDirectional(k)
    if k==keys.up or k==keys.w then return "up"
    elseif k==keys.down or k==keys.s then return "down"
    elseif k==keys.left or k==keys.a then return "left"
    elseif k==keys.right or k==keys.d then return "right"
    end
end

-- ---------------- NETWORK SNAKE ----------------

local function netSnakeRender(st,me)
    local w,h=size()
    cls()
    centerText(1,"SNAKE // LAN",theme.yellow)

    local x1,y1=math.floor((w-st.gw-2)/2)+1,3
    local x2,y2=x1+st.gw+1,y1+st.gh+1
    box(x1,y1,x2,y2," ARENA ")

    writeAt(2,h,"YOU P"..me.."  |  "..st.s1.score.." - "..st.s2.score.."  |  WASD/Fleches",theme.dim)

    writeAt(x1+st.apple.x,y1+st.apple.y,"@",theme.yellow)
    for i,s in ipairs({st.s1,st.s2}) do
        local col=(i==me) and theme.good or theme.accent2
        if not s.alive then col=theme.bad end
        for n,p in ipairs(s.body) do
            writeAt(x1+p.x,y1+p.y,n==1 and "O" or "o",col)
        end
    end
end

local function netSnakeState()
    local gw,gh=39,11
    local function mk(x,y,dx)
        return {body={{x=x,y=y},{x=x-dx,y=y},{x=x-2*dx,y=y}},
                dx=dx,dy=0,nextDx=dx,nextDy=0,alive=true,score=0}
    end
    return {
        gw=gw,gh=gh,
        s1=mk(8,math.floor(gh/2),1),
        s2=mk(gw-8,math.floor(gh/2),-1),
        apple={x=math.floor(gw/2),y=math.floor(gh/2)}
    }
end

local function snakeApplyDir(s,a)
    local dx,dy=s.nextDx,s.nextDy
    if a=="up" then dx,dy=0,-1
    elseif a=="down" then dx,dy=0,1
    elseif a=="left" then dx,dy=-1,0
    elseif a=="right" then dx,dy=1,0
    else return end
    if dx==-s.dx and dy==-s.dy then return end
    s.nextDx,s.nextDy=dx,dy
end

local function netSnakeHost(session)
    math.randomseed(session.seed)
    local st=netSnakeState()

    local function occupied(x,y)
        for _,s in ipairs({st.s1,st.s2}) do
            for _,p in ipairs(s.body) do if p.x==x and p.y==y then return true end end
        end
        return false
    end

    local function apple()
        for _=1,300 do
            local x,y=math.random(1,st.gw),math.random(1,st.gh)
            if not occupied(x,y) then st.apple={x=x,y=y}; return end
        end
    end

    local function bodyHit(head,s,ignoreHead)
        for i,p in ipairs(s.body) do
            if not(ignoreHead and i==1) and p.x==head.x and p.y==head.y then return true end
        end
        return false
    end

    local function tick()
        local ss={st.s1,st.s2}
        local heads={}
        for i,s in ipairs(ss) do
            if s.alive then
                s.dx,s.dy=s.nextDx,s.nextDy
                heads[i]={x=s.body[1].x+s.dx,y=s.body[1].y+s.dy}
            end
        end

        if heads[1] and heads[2] and heads[1].x==heads[2].x and heads[1].y==heads[2].y then
            st.s1.alive=false; st.s2.alive=false
        end

        for i,s in ipairs(ss) do
            local head=heads[i]
            if s.alive and head then
                local other=ss[3-i]
                if head.x<1 or head.x>st.gw or head.y<1 or head.y>st.gh
                    or bodyHit(head,s,false) or bodyHit(head,other,false) then
                    s.alive=false
                end
            end
        end

        local ate=false
        for i,s in ipairs(ss) do
            local head=heads[i]
            if s.alive and head then
                table.insert(s.body,1,head)
                if head.x==st.apple.x and head.y==st.apple.y then
                    s.score=s.score+1
                    ate=true
                else
                    table.remove(s.body)
                end
            end
        end
        if ate then apple() end
    end

    local function finishReason()
        if st.s1.alive and st.s2.alive then return nil end
        if st.s1.alive then return "P1 GAGNE"
        elseif st.s2.alive then return "P2 GAGNE"
        elseif st.s1.score>st.s2.score then return "P1 GAGNE AU SCORE"
        elseif st.s2.score>st.s1.score then return "P2 GAGNE AU SCORE"
        else return "EGALITE" end
    end

    sessionSend(session,{type="state",state=st})
    netSnakeRender(st,1)
    local timer=os.startTimer(0.11)

    while true do
        local ev,a,b,c=os.pullEvent()

        if ev=="key" then
            if a==keys.escape or a==keys.q then
                sessionSend(session,{type="peer_quit"}); return
            end
            local act=netKeyDirectional(a)
            if act then snakeApplyDir(st.s1,act) end

        elseif ev=="rednet_message" and matchingPlayMessage(a,b,c,session) then
            if b.type=="quit" then return
            elseif b.type=="input" then snakeApplyDir(st.s2,b.action) end

        elseif ev=="timer" and a==timer then
            tick()
            netSnakeRender(st,1)
            sessionSend(session,{type="state",state=st})

            local reason=finishReason()
            if reason then
                sessionSend(session,{type="gameover",reason=reason,state=st})
                popup("SNAKE LAN",{reason,st.s1.score.." - "..st.s2.score},"Appuie sur une touche")
                waitKey(); return
            end
            timer=os.startTimer(0.11)
        end
    end
end

local function netSnake(session)
    if session.role=="host" then netSnakeHost(session)
    else clientGameLoop(session,netSnakeRender,netKeyDirectional) end
end

-- ---------------- NETWORK PONG ----------------

local function netPongRender(st,me)
    local w,h=size()
    cls()
    centerText(1,"PONG // LAN",theme.yellow)
    local x1,y1=3,3
    local x2,y2=w-2,h-2
    box(x1,y1,x2,y2," "..st.p1.score.." : "..st.p2.score.." ")

    for y=y1+1,y2-1 do
        if y%2==0 then writeAt(math.floor((x1+x2)/2),y,".",theme.dim) end
    end

    for i=0,st.paddle-1 do
        writeAt(x1+1,st.p1.y+i," ",colors.white,me==1 and theme.good or theme.accent2)
        writeAt(x2-1,st.p2.y+i," ",colors.white,me==2 and theme.good or theme.accent2)
    end
    writeAt(math.floor(st.ball.x),math.floor(st.ball.y),"O",theme.yellow)
    writeAt(2,h,"YOU P"..me.."  WASD/Fleches   Premier a "..st.target,theme.dim)
end

local function netPongHost(session)
    local w,h=size()
    local x1,y1=3,3
    local x2,y2=w-2,h-2
    local st={
        paddle=4,target=7,
        p1={y=math.floor((y1+y2)/2)-1,score=0},
        p2={y=math.floor((y1+y2)/2)-1,score=0},
        ball={x=math.floor((x1+x2)/2),y=math.floor((y1+y2)/2),vx=1,vy=0.7}
    }

    local function clampP(p) p.y=clamp(p.y,y1+1,y2-st.paddle) end
    local function reset(dir)
        st.ball.x=math.floor((x1+x2)/2); st.ball.y=math.floor((y1+y2)/2)
        st.ball.vx=dir or (math.random(0,1)==0 and -1 or 1)
        st.ball.vy=randChoice({-0.8,-0.55,0.55,0.8})
    end
    local function moveP(p,a)
        if a=="up" then p.y=p.y-1 elseif a=="down" then p.y=p.y+1 end
        clampP(p)
    end
    local function step()
        local b=st.ball
        local nx,ny=b.x+b.vx,b.y+b.vy
        if ny<=y1+1 then ny=y1+1; b.vy=math.abs(b.vy)
        elseif ny>=y2-1 then ny=y2-1; b.vy=-math.abs(b.vy) end

        if b.vx<0 and nx<=x1+2 and ny>=st.p1.y and ny<=st.p1.y+st.paddle-1 then
            nx=x1+2; b.vx=math.abs(b.vx)*1.015
            local rel=(ny-(st.p1.y+(st.paddle-1)/2))/st.paddle
            b.vy=clamp(b.vy+rel*0.75,-1.35,1.35)
        elseif b.vx>0 and nx>=x2-2 and ny>=st.p2.y and ny<=st.p2.y+st.paddle-1 then
            nx=x2-2; b.vx=-math.abs(b.vx)*1.015
            local rel=(ny-(st.p2.y+(st.paddle-1)/2))/st.paddle
            b.vy=clamp(b.vy+rel*0.75,-1.35,1.35)
        end

        b.x,b.y=nx,ny
        if b.x<x1+1 then st.p2.score=st.p2.score+1; reset(1)
        elseif b.x>x2-1 then st.p1.score=st.p1.score+1; reset(-1) end
    end

    sessionSend(session,{type="state",state=st})
    netPongRender(st,1)
    local timer=os.startTimer(0.055)

    while true do
        local ev,a,b,c=os.pullEvent()
        if ev=="key" then
            if a==keys.escape or a==keys.q then sessionSend(session,{type="peer_quit"}); return end
            local act=netKeyDirectional(a)
            if act=="up" or act=="down" then moveP(st.p1,act) end

        elseif ev=="rednet_message" and matchingPlayMessage(a,b,c,session) then
            if b.type=="quit" then return
            elseif b.type=="input" and (b.action=="up" or b.action=="down") then moveP(st.p2,b.action) end

        elseif ev=="timer" and a==timer then
            step()
            netPongRender(st,1)
            sessionSend(session,{type="state",state=st})

            if st.p1.score>=st.target or st.p2.score>=st.target then
                local reason=st.p1.score>st.p2.score and "P1 GAGNE" or "P2 GAGNE"
                sessionSend(session,{type="gameover",reason=reason,state=st})
                popup("PONG LAN",{reason,st.p1.score.." - "..st.p2.score},"Appuie sur une touche")
                waitKey(); return
            end
            timer=os.startTimer(0.055)
        end
    end
end

local function netPong(session)
    local function mapper(k)
        local a=netKeyDirectional(k)
        if a=="up" or a=="down" then return a end
    end
    if session.role=="host" then netPongHost(session)
    else clientGameLoop(session,netPongRender,mapper) end
end

-- ---------------- NETWORK TETRIS ----------------

local function netTetrisDrawBoard(p,bx,by,title,col)
    box(bx,by,bx+11,by+p.h+1,title,col)
    for y=1,p.h do
        for x=1,p.w do
            local c=p.grid[y][x]
            writeAt(bx+x,by+y," ",colors.white,c~=0 and c or colors.black)
        end
    end
    if p.piece and not p.dead then
        local cells,pcol=pieceCells(p.piece)
        for _,c in ipairs(cells) do
            if c.y>=1 and c.y<=p.h and c.x>=1 and c.x<=p.w then
                writeAt(bx+c.x,by+c.y," ",colors.white,pcol)
            end
        end
    end
end

local function netTetrisRender(st,me)
    local w,h=size()
    cls()
    centerText(1,"TETRIS VERSUS // LAN",theme.yellow)
    local own=(me==1) and st.p1 or st.p2
    local opp=(me==1) and st.p2 or st.p1
    local bx=math.floor((w-12)/2)+1
    netTetrisDrawBoard(own,bx,3," YOU P"..me.." ",theme.good)

    writeAt(2,4,"YOU",theme.good)
    writeAt(2,5,"Score "..own.score,theme.text)
    writeAt(2,6,"Lines "..own.lines,theme.text)
    writeAt(2,8,"RIVAL",theme.accent2)
    writeAt(2,9,"Score "..opp.score,theme.text)
    writeAt(2,10,"Lines "..opp.lines,theme.text)
    writeAt(2,11,opp.dead and "KO" or "ALIVE",opp.dead and theme.bad or theme.good)
    writeAt(2,h,"WASD/Fleches move | Haut/W rotate | ESPACE hard drop",theme.dim)
end

local function netTetrisAction(p,action,other)
    if p.dead then return end
    local cleared=0
    if action=="left" then movePiece(p,-1,0)
    elseif action=="right" then movePiece(p,1,0)
    elseif action=="down" then
        if not movePiece(p,0,1) then cleared=lockPiece(p) end
    elseif action=="rotate" then rotatePiece(p)
    elseif action=="drop" then cleared=hardDrop(p)
    end
    if other and cleared>=2 then addGarbage(other,cleared-1) end
end

local function tetrisNetKey(k)
    if k==keys.left or k==keys.a then return "left"
    elseif k==keys.right or k==keys.d then return "right"
    elseif k==keys.down or k==keys.s then return "down"
    elseif k==keys.up or k==keys.w then return "rotate"
    elseif k==keys.space or k==keys.enter then return "drop"
    end
end

local function netTetrisHost(session)
    math.randomseed(session.seed)
    local st={p1=newTetrisPlayer("P1",theme.good),p2=newTetrisPlayer("P2",theme.accent2)}
    st.p1.next=randChoice(PIECE_NAMES); spawnPiece(st.p1)
    st.p2.next=randChoice(PIECE_NAMES); spawnPiece(st.p2)

    local function gameover()
        if not st.p1.dead and not st.p2.dead then return nil end
        if st.p1.dead and st.p2.dead then
            if st.p1.score>st.p2.score then return "P1 GAGNE AU SCORE"
            elseif st.p2.score>st.p1.score then return "P2 GAGNE AU SCORE"
            else return "EGALITE" end
        elseif st.p1.dead then return "P2 GAGNE"
        else return "P1 GAGNE" end
    end

    sessionSend(session,{type="state",state=st})
    netTetrisRender(st,1)
    local fall=os.startTimer(0.42)

    while true do
        local ev,a,b,c=os.pullEvent()
        local changed=false

        if ev=="key" then
            if a==keys.escape or a==keys.q then sessionSend(session,{type="peer_quit"}); return end
            local act=tetrisNetKey(a)
            if act then netTetrisAction(st.p1,act,st.p2); changed=true end

        elseif ev=="rednet_message" and matchingPlayMessage(a,b,c,session) then
            if b.type=="quit" then return
            elseif b.type=="input" then netTetrisAction(st.p2,b.action,st.p1); changed=true end

        elseif ev=="timer" and a==fall then
            if not st.p1.dead and not movePiece(st.p1,0,1) then
                local cl=lockPiece(st.p1); if cl>=2 then addGarbage(st.p2,cl-1) end
            end
            if not st.p2.dead and not movePiece(st.p2,0,1) then
                local cl=lockPiece(st.p2); if cl>=2 then addGarbage(st.p1,cl-1) end
            end
            changed=true
            local maxLevel=math.max(st.p1.level or 1,st.p2.level or 1)
            fall=os.startTimer(math.max(0.16,0.42-(maxLevel-1)*0.025))
        end

        if changed then
            netTetrisRender(st,1)
            sessionSend(session,{type="state",state=st})
        end

        local reason=gameover()
        if reason then
            sessionSend(session,{type="gameover",reason=reason,state=st})
            popup("TETRIS LAN",{reason,"P1 "..st.p1.score.." | P2 "..st.p2.score},"Appuie sur une touche")
            waitKey(); return
        end
    end
end

local function netTetris(session)
    if session.role=="host" then netTetrisHost(session)
    else clientGameLoop(session,netTetrisRender,tetrisNetKey) end
end

-- ---------------- NETWORK 2048 ----------------

local function net2048Render(st,me)
    local w,h=size()
    cls()
    centerText(1,"2048 RACE // LAN",theme.yellow)
    local b=(me==1) and st.b1 or st.b2
    local score=(me==1) and st.s1 or st.s2
    local oppScore=(me==1) and st.s2 or st.s1
    local oppBoard=(me==1) and st.b2 or st.b1
    local bx=math.floor((w-22)/2)+1
    draw2048Board(b,bx,3,"YOU P"..me,score,theme.good)
    writeAt(2,5,"RIVAL",theme.accent2)
    writeAt(2,6,"Score "..oppScore,theme.text)
    writeAt(2,7,"Max "..maxTile(oppBoard),theme.text)
    writeAt(2,h,"WASD/Fleches // Premier a 2048 ou dernier vivant",theme.dim)
end

local function net2048Host(session)
    math.randomseed(session.seed)
    local st={b1=new2048Board(),b2=new2048Board(),s1=0,s2=0}
    add2048Tile(st.b1); add2048Tile(st.b1)
    add2048Tile(st.b2); add2048Tile(st.b2)

    local function act(player,dir)
        local b=(player==1) and st.b1 or st.b2
        local changed,gain=move2048(b,dir)
        if changed then
            if player==1 then st.s1=st.s1+gain else st.s2=st.s2+gain end
        end
        return changed
    end

    local function reason()
        local w1=maxTile(st.b1)>=2048
        local w2=maxTile(st.b2)>=2048
        local d1=not can2048Move(st.b1)
        local d2=not can2048Move(st.b2)

        if w1 and not w2 then return "P1 ATTEINT 2048"
        elseif w2 and not w1 then return "P2 ATTEINT 2048"
        elseif d1 and not d2 then return "P2 GAGNE"
        elseif d2 and not d1 then return "P1 GAGNE"
        elseif (w1 and w2) or (d1 and d2) then
            if st.s1>st.s2 then return "P1 GAGNE AU SCORE"
            elseif st.s2>st.s1 then return "P2 GAGNE AU SCORE"
            else return "EGALITE" end
        end
    end

    sessionSend(session,{type="state",state=st})
    net2048Render(st,1)

    while true do
        local ev,a,b,c=os.pullEvent()
        local changed=false

        if ev=="key" then
            if a==keys.escape or a==keys.q then sessionSend(session,{type="peer_quit"}); return end
            local dir=netKeyDirectional(a)
            if dir then changed=act(1,dir) end

        elseif ev=="rednet_message" and matchingPlayMessage(a,b,c,session) then
            if b.type=="quit" then return
            elseif b.type=="input" then changed=act(2,b.action) end
        end

        if changed then
            net2048Render(st,1)
            sessionSend(session,{type="state",state=st})
            local r=reason()
            if r then
                sessionSend(session,{type="gameover",reason=r,state=st})
                popup("2048 LAN",{r,"P1 "..st.s1.." | P2 "..st.s2},"Appuie sur une touche")
                waitKey(); return
            end
        end
    end
end

local function net2048(session)
    if session.role=="host" then net2048Host(session)
    else clientGameLoop(session,net2048Render,netKeyDirectional) end
end

-- ---------------- NETWORK MINESWEEPER ----------------

local function mineProgress(p)
    local n=0
    for y=1,p.h do for x=1,p.w do
        if p.revealed[y][x] and not p.mines[y][x] then n=n+1 end
    end end
    return n
end

local function netMinesRender(st,me)
    local w,h=size()
    cls()
    centerText(1,"MINESWEEPER RACE // LAN",theme.yellow)
    local p=(me==1) and st.p1 or st.p2
    local opp=(me==1) and st.p2 or st.p1
    local bx=math.floor((w-p.w-2)/2)+1
    drawMineBoard(p,bx,3,"YOU P"..me,theme.good)
    writeAt(2,5,"RIVAL",theme.accent2)
    writeAt(2,6,"Safe "..mineProgress(opp),theme.text)
    writeAt(2,7,opp.dead and "BOOM" or (opp.won and "DONE" or "PLAYING"),
        opp.dead and theme.bad or theme.text)
    writeAt(2,h-1,"WASD/Fleches move | ENTER/E reveal | F/R flag",theme.dim)
    writeAt(2,h,"Meme grille sur les deux PC. Une mine = defaite.",theme.dim)
end

local function minesNetKey(k)
    if k==keys.up or k==keys.w then return "up"
    elseif k==keys.down or k==keys.s then return "down"
    elseif k==keys.left or k==keys.a then return "left"
    elseif k==keys.right or k==keys.d then return "right"
    elseif k==keys.enter or k==keys.e then return "reveal"
    elseif k==keys.f or k==keys.r then return "flag"
    end
end

local function netMinesHost(session)
    math.randomseed(session.seed)
    local gw,gh,mines=12,10,18
    local layout=makeMineLayout(gw,gh,mines)
    local st={p1=newMinePlayer(gw,gh,layout),p2=newMinePlayer(gw,gh,layout)}

    local function act(p,a)
        if p.dead or p.won then return end
        if a=="up" then p.cy=clamp(p.cy-1,1,p.h)
        elseif a=="down" then p.cy=clamp(p.cy+1,1,p.h)
        elseif a=="left" then p.cx=clamp(p.cx-1,1,p.w)
        elseif a=="right" then p.cx=clamp(p.cx+1,1,p.w)
        elseif a=="flag" then
            if not p.revealed[p.cy][p.cx] then p.flags[p.cy][p.cx]=not p.flags[p.cy][p.cx] end
        elseif a=="reveal" then
            revealMineCell(p,p.cx,p.cy)
            checkMineWin(p)
        end
    end

    local function reason()
        if st.p1.won and st.p2.won then return "EGALITE"
        elseif st.p1.won then return "P1 GAGNE"
        elseif st.p2.won then return "P2 GAGNE"
        elseif st.p1.dead and st.p2.dead then return "DOUBLE BOOM"
        elseif st.p1.dead then return "P2 GAGNE"
        elseif st.p2.dead then return "P1 GAGNE"
        end
    end

    sessionSend(session,{type="state",state=st})
    netMinesRender(st,1)

    while true do
        local ev,a,b,c=os.pullEvent()
        local changed=false

        if ev=="key" then
            if a==keys.escape or a==keys.q then sessionSend(session,{type="peer_quit"}); return end
            local input=minesNetKey(a)
            if input then act(st.p1,input); changed=true end

        elseif ev=="rednet_message" and matchingPlayMessage(a,b,c,session) then
            if b.type=="quit" then return
            elseif b.type=="input" then act(st.p2,b.action); changed=true end
        end

        if changed then
            netMinesRender(st,1)
            sessionSend(session,{type="state",state=st})
            local r=reason()
            if r then
                sessionSend(session,{type="gameover",reason=r,state=st})
                popup("MINESWEEPER LAN",{r},"Appuie sur une touche")
                waitKey(); return
            end
        end
    end
end

local function netMines(session)
    if session.role=="host" then netMinesHost(session)
    else clientGameLoop(session,netMinesRender,minesNetKey) end
end

local NETWORK_GAMES = {
    snake=netSnake,
    pong=netPong,
    tetris=netTetris,
    game2048=net2048,
    minesweeper=netMines,
}

local function gameLauncher(gameKey,title,soloFn)
    local sel=1
    local opts={"SOLO","MULTIPLAYER LAN","RETOUR"}

    while true do
        cls()
        centerText(2,"TRMK GAME CONSOLE",theme.accent)
        centerText(4,title,theme.yellow)
        local w=size()
        local bw=30
        local x=math.floor((w-bw)/2)+1
        for i,opt in ipairs(opts) do button(x,7+(i-1)*2,x+bw-1,opt,i==sel) end
        centerText(15,"MULTI = 1 ordinateur par joueur",theme.dim)

        local _,k=os.pullEvent("key")
        if k==keys.up or k==keys.w then sel=sel-1 if sel<1 then sel=#opts end
        elseif k==keys.down or k==keys.s then sel=sel+1 if sel>#opts then sel=1 end
        elseif k==keys.escape or k==keys.q then return
        elseif k==keys.enter then
            if sel==1 then
                soloFn()
            elseif sel==2 then
                local session=multiplayerMenu(gameKey,title)
                if session then
                    local runner=NETWORK_GAMES[gameKey]
                    if runner then runner(session) end
                end
            else
                return
            end
        end
    end
end

-- ================================================================
-- SCORES / HELP / MENU
-- ================================================================

local function scoreScreen()
    while true do
        cls(); centerText(2,"TRMK HALL OF FAME",theme.accent); local w=size(); box(7,4,w-6,15," LOCAL SCORES ")
        writeAt(10,6,"Snake       "..tostring(save.scores.snake or 0),theme.good)
        writeAt(10,8,"Pong wins   "..tostring(save.scores.pong or 0),theme.accent2)
        writeAt(10,10,"Tetris      "..tostring(save.scores.tetris or 0),theme.accent)
        writeAt(10,12,"2048        "..tostring(save.scores.game2048 or 0),theme.yellow)
        local mt=save.scores.minesweeper; local mtxt=(mt and mt<999999) and string.format("%.1fs",mt) or "--"
        writeAt(10,14,"Minesweeper "..mtxt,theme.magenta)
        centerText(17,"ESC / ENTER pour revenir",theme.dim)
        local _,k=os.pullEvent("key"); if k==keys.escape or k==keys.enter or k==keys.q then return end
    end
end

local function helpScreen()
    local pages={
        {title="MULTIPLAYER LAN",lines={
            "Chaque joueur utilise SON propre ordinateur.",
            "Branche un modem sur les deux PC.",
            "Wired Modem : meme reseau de cables.",
            "Wireless Modem : meme portee radio.",
            "Host Game sur un PC, Join Game sur l'autre."
        }},
        {title="SNAKE / PONG",lines={
            "Sur chaque PC : WASD ou Fleches.",
            "Snake : meme arene synchronisee.",
            "Pong : chacun controle sa raquette.",
            "Le host est l'autorite de la partie."
        }},
        {title="TETRIS",lines={
            "Chaque joueur voit sa grille en grand.",
            "WASD/Fleches : mouvement.",
            "Haut/W : rotation. ESPACE : hard drop.",
            "2+ lignes envoient du garbage au rival."
        }},
        {title="2048 / MINESWEEPER",lines={
            "2048 : chacun son plateau, course en direct.",
            "Minesweeper : meme grille pour les deux.",
            "Mines : ENTER/E reveal, F/R flag.",
            "ESC quitte proprement une partie LAN."
        }}
    }
    local page=1
    while true do
        cls()
        centerText(2,"TRMK GAME CONSOLE - HELP",theme.accent)
        local w=size()
        box(4,4,w-3,15,pages[page].title)
        local y=6
        for _,l in ipairs(pages[page].lines) do writeAt(7,y,l,theme.text); y=y+1 end
        centerText(17,string.format("Gauche/Droite page %d/%d    ESC retour",page,#pages),theme.dim)
        local _,k=os.pullEvent("key")
        if k==keys.left then page=page-1 if page<1 then page=#pages end
        elseif k==keys.right then page=page+1 if page>#pages then page=1 end
        elseif k==keys.escape or k==keys.q or k==keys.enter then return end
    end
end

local games={
    {name="SNAKE",desc="Solo + arene LAN",color=theme.good,
        run=function() gameLauncher("snake","SNAKE",function() snakeGame("solo") end) end},
    {name="PONG",desc="IA + duel LAN",color=theme.accent2,
        run=function() gameLauncher("pong","PONG",function() pongGame("solo") end) end},
    {name="TETRIS",desc="Solo + garbage LAN",color=theme.accent,
        run=function() gameLauncher("tetris","TETRIS",function() tetrisGame("solo") end) end},
    {name="2048",desc="Solo + race LAN",color=theme.yellow,
        run=function() gameLauncher("game2048","2048",function() game2048("solo") end) end},
    {name="MINESWEEPER",desc="Solo + race LAN",color=theme.magenta,
        run=function() gameLauncher("minesweeper","MINESWEEPER",function() minesweeperGame("solo") end) end},
}

local function mainMenu()
    local sel=1; local entries=#games+3
    while true do
        cls(); centerText(1,"TRMK GAME CONSOLE",theme.accent); centerText(2,"V2 // LAN ARCADE SYSTEM",theme.dim)
        local w,h=size(); local left,right=4,w-3; box(left,4,right,h-2," GAMES ")
        for i,g in ipairs(games) do
            local y=5+(i-1)*2; local active=sel==i; local bg=active and g.color or theme.bg; local fg=active and colors.black or g.color
            fill(left+2,y,right-2,y,bg); writeAt(left+4,y,trunc(g.name,16),fg,bg); writeAt(left+19,y,trunc(g.desc,right-left-22),active and colors.black or theme.dim,bg)
        end
        local yBase=5+#games*2; local extra={{"HALL OF FAME"},{"CONTROLES / HELP"},{"QUITTER"}}
        for i,e in ipairs(extra) do local idx=#games+i; button(left+2,yBase+i-1,right-2,e[1],sel==idx) end
        writeAt(2,h,"Haut/Bas naviguer   ENTER jouer   ESC quitter",theme.dim)
        local _,k=os.pullEvent("key")
        if k==keys.up or k==keys.w then sel=sel-1; if sel<1 then sel=entries end
        elseif k==keys.down or k==keys.s then sel=sel+1; if sel>entries then sel=1 end
        elseif k==keys.enter then
            if sel<=#games then save.totalPlays=save.totalPlays+1; saveData(); games[sel].run()
            elseif sel==#games+1 then scoreScreen() elseif sel==#games+2 then helpScreen() else return end
        elseif k==keys.escape or k==keys.q then return end
    end
end

local function boot()
    if not ensureTerminal() then return end
    cls(); centerText(5,"TRMK",theme.accent); centerText(7,"GAME CONSOLE",theme.text); centerText(10,"Loading arcade modules...",theme.dim)
    local w=size(); local barW=math.min(34,w-8); local x=math.floor((w-barW)/2)+1
    fill(x,12,x+barW-1,12,theme.panel)
    for i=1,barW do fill(x,12,x+i-1,12,theme.accent); sleep(0.012) end
    mainMenu(); cls(); centerText(8,"TRMK GAME CONSOLE",theme.accent); centerText(10,"SYSTEM OFF",theme.dim); sleep(0.4); cls()
end

local ok,err=pcall(boot)
term.setCursorBlink(false); term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
if not ok then printError("TRMK Game Console crashed:"); printError(err) end
