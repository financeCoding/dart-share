library hex_demo;

import 'dart:html';
import 'dart:isolate';
import 'dart:math' as Math;

import 'package:share/client.dart' as share;
import 'package:share/src/client/ws/connection.dart' as ws;

randomDocName([length = 10]) {
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=";
  var name = [];
  var rnd = new Math.Random();
  for (var x = 0; x < length; x++) {
    name.add(chars[rnd.nextInt(chars.length)]);
  }
  return Strings.join(name, '');
}

      // from http://www.quirksmode.org/js/cookies.html
createCookie(name,value,days) {
  var expires = "";
  if (days) {
    var date = new Date.now();
    date.add(new Duration(days: days));
    var expires = "; expires=${date.toString()}";
  }
  document.cookie = "$name=$value$expires; path=/";
}

readCookie(name) {
  var nameEQ = "$name=";
  var ca = document.cookie.split(';');
  for(var i=0;i < ca.length;i++) {
    var c = ca[i];
    while (c.startsWith(' ')) c = c.substring(1);
    if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
  }
  return null;
}

eraseCookie(name) => createCookie(name,"",-1);

var defaultSide = 20, 
    spacing = 5,
    selectedX = null,
    selectedY = null,
    grid = {"width": 10, "height": 10},
    playerTurn = 1,
    playerColors = [[200,0,0], [0,0,200]];

gridAt(g,x,y) => g.values[y*g.width+x];

colorStyle(color) => 'rgb(${color[0]},${color[1]},${color[2]})';

fillHex(ctx, x, y, color, side) {
  ctx.fillStyle = color;
  x += 0.5;
  y += 0.5;
  pathHex(ctx, x, y, color, side);
  ctx.fill();
}

strokeHex(ctx, x, y, color, side) {
  ctx.strokeStyle = color;
  x += 0.5;
  y += 0.5;
  pathHex(ctx, x, y, color, side);
  ctx.stroke();
}

pathHex(ctx, x, y, color, side) {
  if (!side) side = defaultSide;
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(x+side, y);
  ctx.lineTo(x+side+side*Math.cos(Math.PI/3),
      y+side*Math.sin(Math.PI/3));
  ctx.lineTo(x+side, y+2*side*Math.sin(Math.PI/3));
  ctx.lineTo(x, y+2*side*Math.sin(Math.PI/3));
  ctx.lineTo(x-side*Math.cos(Math.PI/3), y+side*Math.sin(Math.PI/3));
  ctx.lineTo(x, y);
}

hexEdgeWidth(side) {
  //  _
  // / \
  // \_/
  //   v ~~~~ this width

  if (!side) side = defaultSide;
  return side*Math.cos(Math.PI/3);
}

hexHeight(side) {
  // height of one hex of side length +side+
  if (!side) side = defaultSide;
  return 2*side*Math.sin(Math.PI/3);
}

adjacencies(x, y) {
  // odd and even columns have different adjacencies
  var odd = (x % 2 == 0) ? -1 : 1;
  return [[x-1,y], [x+1,y], [x, y-1], [x, y+1],
          [x-1, y+odd], [x+1,y+odd]];
}

all(f, xs) {
  for (var i = 0; i < xs.length; i++) {
    if (!f(xs[i])) {
      return false;
    }
  }
  return true;
}

any(f, xs) {
  for (var i = 0; i < xs.length; i++) {
    if (f(xs[i])) {
      return true;
    }
  }
  return false;
}

okToPlace(gr, player, x, y) {
  if (x < 0 || x >= gr.width || y < 0 || y >= gr.height) return false;
  if (gridAt(gr, x,y) != 0) return false;
  // a move adjacent to (x,y) would be OK
  var adjMoveOK = (xy) {
    var x = xy[0], y = xy[1];
    if (x < 0 || x >= gr.width || y < 0 || y >= gr.width) {
      return true;
    }
    var val = gridAt(gr, x,y);
    return val == 0 || val == player;
  };
  return (all(adjMoveOK, adjacencies(x,y)));
}

drawGrid(ctx, gr) {
  for (var y = 0; y < gr.height; y++) {
    for (var x = 0; x < gr.width; x++) {
      var hexX = hexEdgeWidth() + (defaultSide+hexEdgeWidth() +
          spacing*Math.cos(Math.PI/6))*x;
      var hexY = (hexHeight() + spacing)*y +
          (x % 2 == 0 ? 0 :
            spacing*Math.sin(Math.PI/6) +
            hexHeight()/2);

      var value = gridAt(gr,x,y);
      if (value != 0) {
        var fillColor = colorStyle(playerColors[value-1]);
        fillHex(ctx, hexX, hexY, fillColor);
      }

      var strokeColor = 'rgb(0,0,0)';
      var ok1 = okToPlace(gr, 1, x, y),
          ok2 = okToPlace(gr, 2, x, y);
      if (ok1 && !ok2) {
        strokeColor = 'rgb(250,140,140)';
      } else if (!ok1 && ok2) {
        strokeColor = 'rgb(140,140,250)';
      } else if (!ok1 && !ok2) {
        strokeColor = 'rgb(255,255,255)';
      }
      if (x == selectedX && y == selectedY) {
        strokeColor = 'rgb(0,200,0)';
      }

      strokeHex(ctx, hexX, hexY, strokeColor);
    }
  }
}

yForX(m, b, x) => m*x + b; // y = mx + b

hexForPixel(x,y) {
  // take the pixel (x,y) and return the coordinates of the hex under
  // that pixel
  var xspacing = Math.cos(Math.PI/6)*spacing;
  x += xspacing;
  var cellwidth = defaultSide + hexEdgeWidth() + xspacing;
  var cellheight = hexHeight() + spacing;
  var xcell = (x / cellwidth).floor();
  // determine if we're in an odd column
  var odd = xcell % 2 != 0;
  if (odd) {
    y -= cellheight/2;
  }
  var ycell = (y / cellheight).floor();
  var xoff = x - xcell*cellwidth;
  var yoff = y - ycell*cellheight;

  var s3 = Math.sqrt(3);
  // top line
  var t_m = -s3, t_b = s3*(xspacing + hexEdgeWidth());
  // bottom line
  var b_m = s3, b_b = hexHeight()/2 - s3*xspacing;

  if ((xoff >= hexEdgeWidth() + xspacing && yoff <= hexHeight()) ||
      (xoff >= xspacing && xoff < hexEdgeWidth() + xspacing &&
      yoff >= yForX(t_m, t_b, xoff) &&
      yoff <= yForX(b_m, b_b, xoff))
  ) {
    return {x:xcell, y:ycell};
  }
  if (yoff <= hexHeight()/2 && yoff <= yForX(t_m, hexHeight()/2, xoff)) {
    return {x:xcell-1, y:ycell + (odd ? 0 : -1)};
  }
  if (yoff >= hexHeight()/2 + spacing &&
      yoff >= yForX(b_m, spacing + hexHeight() / 2, xoff)) {
    return {x:xcell-1, y:ycell + (odd ? 1 : 0)};
  }
}

isComplete(gr) {
  for (var y = 0; y < gr.height; y++) {
    for (var x = 0; x < gr.width; x++) {
      var ok1 = okToPlace(gr, 1, x, y),
          ok2 = okToPlace(gr, 2, x, y);
      if (ok1 && ok2) {
        // either player can place; board not complete.
        return false;
      } else if (ok1 && !ok2) {
        // player 1 can place. if player 2 can place at any point
        // adjacent to this one, the board is not complete.
        if (any(function (xy) { return okToPlace(gr, 2, xy[0], xy[1]); },
            adjacencies(x,y))) {
          return false;
        }
      } else if (!ok1 && ok2) {
        // player 2 can place. if player 1 can place at any point
        // adjacent to this one, the board is not complete.
        if (any(function (xy) { return okToPlace(gr, 1, xy[0], xy[1]); },
            adjacencies(x,y))) {
          return false;
        }
      } else if (!ok1 && !ok2) {
        // no-man's land
      }
    }
  }
  return true;
}

controller(gr, x, y) {
  var ok1 = okToPlace(gr, 1, x, y) || gridAt(gr, x,y) == 1,
      ok2 = okToPlace(gr, 2, x, y) || gridAt(gr, x,y) == 2;
  if (ok1 && !ok2) return 1;
  if (ok2 && !ok1) return 2;
  return 0;
}

territory(gr, player) {
  var num = 0;
  for (var y = 0; y < gr.height; y++) {
    for (var x = 0; x < gr.width; x++) {
      if (controller(gr, x, y) == player) {
        num++;
      }
    }
  }
  return num;
}

mousePos(ev) {
  var posx = 0;
  var posy = 0;
  if (!e) var e = window.event;
  if (e.pageX || e.pageY)   {
    posx = e.pageX;
    posy = e.pageY;
  } else if (e.clientX || e.clientY)  {
    posx = e.clientX + document.body.scrollLeft
        + document.documentElement.scrollLeft;
    posy = e.clientY + document.body.scrollTop
        + document.documentElement.scrollTop;
  }
  return {x:posx,y:posy}
}

boardMouseMoved(e) {
  var board = $('#board').offset();
  var pos = mousePos(e);
  var x = pos.x - board.left, y = pos.y - board.top;

  var hex = hexForPixel(x,y);
  if (hex) {
    selectedX = hex.x;
    selectedY = hex.y;
  } else {
    selectedX = null;
    selectedY = null;
  }
  redraw();
}

boardMouseClicked(e) {
  var board = $('#board').offset();
  var pos = mousePos(e);
  var x = pos.x - board.left, y = pos.y - board.top;
  var hex = hexForPixel(x,y);
  if (hex && hex.x >= 0 && hex.x < grid.width &&
      hex.y >= 0 && hex.y < grid.height &&
      okToPlace(grid, playerTurn, hex.x, hex.y)) {
    //grid.values[hex.y*grid.width+hex.x] = playerTurn;
    $state.submitOp([{
      p:['grid','values',hex.y*grid.width+hex.x],
      ld:0,li:playerTurn
    },{
      p:['playerTurn'],
      od:playerTurn,
      oi:playerTurn == 1 ? 2 : 1
    }]);
  }
}

redraw() {
  var board = document.getElementById('board');
  var ctx = board.getContext('2d');
  ctx.clearRect(0,0,board.width, board.height);
  drawGrid(ctx, grid);

  ctx.font = '30px sans-serif';
  ctx.textBaseline = 'top';
  ctx.fillStyle = colorStyle(playerColors[playerTurn-1]);
  ctx.fillText('Player ' + playerTurn, 400,100);

  ctx.font = '20px sans-serif';
  ctx.fillStyle = colorStyle(playerColors[0]);
  ctx.fillText('P1: ' + territory(grid, 1), 400,140);

  ctx.fillStyle = colorStyle(playerColors[1]);
  ctx.fillText('P2: ' + territory(grid, 2), 400,165);

  if (isComplete(grid)) {
    ctx.fillStyle = '#000';
    ctx.fillText('Board complete!', 400,200);
  }
}

clear() {
  grid.values = [];
  for (var y = 0; y < grid.height; y++) {
    for (var x = 0; x < grid.width; x++) {
      grid.values[y*grid.width+x] = 0;
    }
  }
}

reset() {
  clear();
  playerTurn = 1;
  $state.submitOp([
                   {p:['grid','values'],od:$state.snapshot.grid.values,oi:grid.values},
                   {p:['playerTurn'],od:$state.snapshot.playerTurn,oi:playerTurn}
                   ]);
}

begin() {
  var board = document.getElementById('board');
  board.onmousemove = boardMouseMoved;
  board.onclick = boardMouseClicked;
  redraw();
}

hue2rgb(p, q, t) {
  if(t < 0) t += 1;
  if(t > 1) t -= 1;
  if(t < 1/6) return p + (q - p) * 6 * t;
  if(t < 1/2) return q;
  if(t < 2/3) return p + (q - p) * (2/3 - t) * 6;
  return p;
}

hslToRgb(h, s, l){
  var r, g, b;

  if(s == 0){
    r = g = b = l; // achromatic
  } else {
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    var p = 2 * l - q;
    r = hue2rgb(p, q, h + 1/3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1/3);
  }

  return '#' + Math.round(r * 255).toString(16) + Math.round(g * 255).toString(16) + Math.round(b * 255).toString(16);
}

colorForName(name) {
  var x = 0;
  var p = 31;
  for (var i = 0; i < name.length; i++) {
    var c = name.charCodeAt(i);
    x += c * p;
    p *= p;
    x = x % 4294967295;
  }
  var h = (x % 89)/89;
  var color = hslToRgb(h, 0.7, 0.3);
  return color;
}

addChatMessage(m) {
  var msg = $('<div class="message"><div class="user"></div><div class="text"></div></div>');
  $('.text', msg).text(m.message);
  $('.user', msg).text(m.from);
  $('.user', msg).css('color',colorForName(m.from));
  $('#chat #messages').append(msg);
  var allMsgs = $('.message')
      if (allMsgs.length > 15) {
        allMsgs.slice(0, Math.max(0,allMsgs.length - 15)).each(function () {
          var e = $(this);
          e.fadeOut('slow', function () {
            e.remove();
          });
        });
      }
}

stateUpdated(op) {
  if (op) {
    var ops = $('#ops');
    var opel = $('<div class="op" style="display:none">');
    opel.text(JSON.stringify(op));
    ops.prepend(opel);
    opel.fadeIn('fast')
    var allOps = $('.op');
    if (allOps.length > 10) {
      allOps.slice(0, Math.max(0,allOps.length - 10)).each(function () {
        var e = $(this);
        e.fadeOut('fast', function () {
          e.remove();
        });
      });
    }
    op.forEach(function (c) {
      if (c.p[0] == 'chat' && c.li) {
        addChatMessage(c.li)
      }
    })
  } else {
    // first run
    $state.snapshot.chat.slice(0, 10).reverse().forEach(addChatMessage)
  }
  $('#doc').text(JSON.stringify($state.snapshot))
  grid = $state.snapshot.grid
  playerTurn = $state.snapshot.playerTurn;
  redraw();
}

main(){
      var username;
      if (!(username = readCookie('username'))) {
        username = randomDocName(4);
        createCookie('username', username, 5);
      }

      query('#message').on.keyDown.add( (e) {
        if ((e.keyCode == 13) || (e.which == 13)) {
          if ((e.srcElement as InputElement).value == null) return;
          // enter was pressed
          $state.submitOp({
            p: ['chat',0],
            li: {
              from: username,
              message: e.srcElement.value
            }
          });
          (e.srcElement as InputElement).value = '';
        }
      });

      

      var $state;
      if (!document.location.hash) {
        document.location.hash = '#' + randomDocName();
      }
      var docname = 'hex:' + document.location.hash.slice(1)

      var client = new share.Client(new ws.Connection());

      var connection = client.open(docname, 'json', 'localhost:8000').then((doc) {
        $state = doc;
        doc.on.change.add(stateUpdated);
        if (doc.created) {
          clear()
          doc.submitOp([{p:[],od:null,oi:{grid:grid,playerTurn:1,chat:[]}}])
        } else {
          stateUpdated();
        }
        begin();
      });
}
