<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Khala Studio — A world between the pages</title>
<style>
:root{
  --ink:#252522; --paper:#F2EDE3; --paper-deep:#E7DECF; --stone:#D9CFBE;
  --terracotta:#A94F3D; --brass:#B08B5A; --green:#68786D; --warm-grey:#77716A;
  --wood:#302820; --wood-light:#403328; --muted:#938879; --line:#D0C4B2;
  --serif: Georgia, "Noto Serif SC", "Songti SC", "STSong", serif;
  --sans: Inter, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif;
}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%;background:var(--wood);color:var(--ink);font-family:var(--sans)}
button{font:inherit;cursor:pointer}
button:focus-visible,[contenteditable="true"]:focus-visible{outline:2px solid var(--terracotta);outline-offset:3px}
.app{min-height:100vh;background:var(--wood);position:relative;overflow:hidden}
/* Bookshelf */
.bookshelf{min-height:100vh;padding:34px clamp(24px,5vw,84px) 64px;color:#F2EDE3;background:#302820;transition:opacity .45s ease,transform .75s ease}
.brandbar{display:flex;align-items:center;justify-content:space-between;max-width:1320px;margin:0 auto 64px}
.brand{display:flex;align-items:center;gap:13px;letter-spacing:.14em;font-size:13px;font-weight:600}
.brand-mark{width:34px;height:34px;border:1px solid #B08B5A;border-radius:3px;display:grid;place-items:center;color:#D3B887;font-family:var(--serif);font-size:20px;letter-spacing:0;box-shadow:inset 0 0 0 3px #302820,inset 0 0 0 4px #B08B5A}
.brand small{display:block;color:#B7AA98;font-size:9px;letter-spacing:.22em;margin-top:4px;font-weight:400}
.top-note{color:#B7AA98;font-size:11px;letter-spacing:.12em}
.shelf-intro{max-width:1320px;margin:0 auto 34px;display:flex;align-items:flex-end;justify-content:space-between;gap:24px}
.kicker{font-size:10px;letter-spacing:.22em;color:#B08B5A;text-transform:uppercase}
.shelf-intro h1{font-family:var(--serif);font-size:clamp(34px,4vw,52px);font-weight:400;line-height:1.15;margin:12px 0 8px;color:#F2EDE3}
.shelf-intro p{margin:0;color:#B7AA98;font-family:var(--serif);font-size:16px}
.new-book{border:1px solid #8E7961;color:#E9DDCB;background:transparent;padding:12px 17px;border-radius:2px;font-size:12px;letter-spacing:.05em}
.new-book:hover{background:#403328;border-color:#B08B5A}
.shelf{max-width:1320px;margin:0 auto;display:grid;grid-template-columns:repeat(3,minmax(210px,1fr));gap:42px 38px;align-items:start}
.book-card{min-width:0;max-width:340px;justify-self:center;width:100%;cursor:pointer;perspective:1200px}
.book-object{height:380px;position:relative;transform-style:preserve-3d;transition:transform .35s ease;filter:drop-shadow(0 16px 18px rgba(0,0,0,.25))}
.book-card:hover .book-object{transform:translateY(-8px) rotateY(-3deg)}
.book-pages-edge{position:absolute;top:8px;right:0;width:23px;height:360px;background:#E8DFD0;border:1px solid #C9BDAA;box-shadow:inset -5px 0 #D6C9B6;transform:translateZ(-5px)}
.book-cover{position:absolute;inset:0 16px 0 0;border-radius:4px 8px 8px 4px;background:var(--cover);border:1px solid var(--cover-edge);transform-origin:left center;transform-style:preserve-3d;box-shadow:inset 8px 0 10px rgba(0,0,0,.18),inset -3px 0 5px rgba(255,255,255,.08),4px 3px 0 rgba(0,0,0,.16);overflow:hidden}
.book-cover:before{content:"";position:absolute;inset:12px;border:1px solid var(--foil);opacity:.75;border-radius:2px;pointer-events:none}
.book-cover:after{content:"";position:absolute;left:19px;top:0;bottom:0;width:9px;border-left:1px solid rgba(255,255,255,.16);border-right:1px solid rgba(0,0,0,.18);box-shadow:3px 0 6px rgba(0,0,0,.12)}
.cover-content{position:absolute;inset:0;padding:42px 36px 30px 48px;display:flex;flex-direction:column;align-items:center;text-align:center;color:var(--cover-text);transform:translateZ(1px)}
.cover-rule{height:1px;width:72%;background:var(--foil);opacity:.75;margin:8px 0}
.cover-emblem{width:44px;height:44px;border:1px solid var(--foil);border-radius:50%;display:grid;place-items:center;color:var(--foil);font-family:var(--serif);font-size:23px;margin:26px 0 20px}
.cover-title{font-family:var(--serif);font-size:32px;line-height:1.15;font-weight:400;margin:0 0 12px;text-shadow:0 1px 1px rgba(0,0,0,.18)}
.cover-sub{font-family:var(--serif);font-size:12px;letter-spacing:.13em;opacity:.82}
.cover-bottom{margin-top:auto;font-size:9px;letter-spacing:.2em;opacity:.78}
.book-spine{position:absolute;left:0;top:0;bottom:0;width:28px;background:rgba(0,0,0,.13);border-right:1px solid rgba(255,255,255,.16);z-index:2}
.book-spine:after{content:"";position:absolute;left:8px;top:16px;bottom:16px;border-left:1px solid rgba(255,255,255,.18)}
.book-meta{display:flex;justify-content:space-between;align-items:center;margin:17px 2px 0;color:#E8DDCE;font-family:var(--serif);font-size:15px}
.book-meta small{font-family:var(--sans);font-size:10px;letter-spacing:.09em;color:#B7AA98}
.shelf-caption{max-width:1320px;margin:56px auto 0;padding-top:19px;border-top:1px solid #514538;color:#8E8171;font-size:10px;letter-spacing:.13em;display:flex;justify-content:space-between}
/* opening transition */
.opening{position:fixed;inset:0;z-index:20;background:var(--wood);display:none;place-items:center;perspective:1800px}
.opening.active{display:grid}
.opening-book{position:relative;width:min(620px,70vw);height:min(440px,58vw);min-height:300px;transform-style:preserve-3d;}
.opening-pages{position:absolute;inset:0 0 0 8px;background:var(--paper);border:1px solid #D4C6B1;box-shadow:0 20px 40px rgba(0,0,0,.35);}
.opening-pages:before{content:"";position:absolute;left:50%;top:0;bottom:0;border-left:1px solid #C8BBA8;box-shadow:-4px 0 9px rgba(0,0,0,.08)}
.opening-cover{position:absolute;inset:0 0 0 0;background:var(--cover-active,#713D3B);border:2px solid var(--foil-active,#C49A78);transform-origin:left center;transform-style:preserve-3d;z-index:3;box-shadow:inset 9px 0 12px rgba(0,0,0,.22),8px 8px 22px rgba(0,0,0,.3)}
.opening-cover:before{content:"";position:absolute;inset:15px;border:1px solid var(--foil-active,#C49A78)}
.opening-cover .cover-content{padding-top:70px}
.opening.active .opening-cover{animation:openCover 1.65s cubic-bezier(.62,.02,.22,1) forwards}
@keyframes openCover{0%{transform:rotateY(0)}68%{transform:rotateY(-166deg)}100%{transform:rotateY(-180deg)}}
.opening-caption{position:absolute;bottom:9vh;color:#B7AA98;font-family:var(--serif);font-size:15px;letter-spacing:.12em;opacity:0;animation:captionIn .5s 1s forwards}
@keyframes captionIn{to{opacity:1}}
/* Studio */
.studio{position:fixed;inset:0;display:none;opacity:0;transform:scale(.985);transition:opacity .5s ease,transform .6s ease;background:var(--wood);padding:22px 28px 26px;overflow:auto}
.studio.active{display:block}
.studio.visible{opacity:1;transform:scale(1)}
.studio-head{max-width:1500px;margin:0 auto 14px;display:flex;align-items:center;justify-content:space-between;color:#E8DDCE;min-height:34px}
.studio-brand{display:flex;align-items:center;gap:10px;font-size:11px;letter-spacing:.15em}
.studio-brand .brand-mark{width:27px;height:27px;font-size:16px}
.studio-world{font-family:var(--serif);font-size:13px;color:#B8A996;letter-spacing:.04em}
.head-actions{display:flex;align-items:center;gap:10px}
.head-btn{border:1px solid #655542;color:#E8DDCE;background:transparent;padding:8px 11px;border-radius:2px;font-size:10px;letter-spacing:.04em}
.head-btn:hover{border-color:#B08B5A;background:#403328}
.open-book{width:min(1500px,100%);height:calc(100vh - 104px);min-height:650px;max-height:900px;margin:0 auto;position:relative;display:grid;grid-template-columns: minmax(0, .92fr) minmax(0,1.08fr);perspective:2200px;filter:drop-shadow(0 16px 28px rgba(0,0,0,.34));}
.page{position:relative;background:var(--paper);min-width:0;overflow:hidden;box-shadow:inset 0 0 0 1px #D3C6B4;}
.page.left{border-radius:9px 0 0 7px;padding:34px 34px 28px 44px;background:#EDE5D8;box-shadow:inset 5px 0 12px rgba(82,63,40,.08),inset -12px 0 16px rgba(89,68,45,.08)}
.page.right{border-radius:0 9px 7px 0;padding:34px 48px 28px 38px;box-shadow:inset 12px 0 17px rgba(89,68,45,.09),inset -5px 0 12px rgba(82,63,40,.06)}
.page.left:after,.page.right:after{content:"";position:absolute;left:18px;right:18px;bottom:13px;border-top:1px solid #D7CCBB;pointer-events:none}
.spine{position:absolute;z-index:4;top:0;bottom:0;left:calc(50% - 10px);width:20px;pointer-events:none;background:#D4C7B4;opacity:.38;box-shadow:0 0 9px rgba(68,49,29,.16)}
.spine:after{content:"";position:absolute;left:9px;top:0;bottom:0;border-left:1px solid rgba(106,85,58,.25)}
.page-head{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #D6CABA;padding-bottom:13px;margin-bottom:22px;color:#817668;font-size:9px;letter-spacing:.17em;text-transform:uppercase}
.page-head strong{font-weight:500;color:#A18A6C}
.left-heading{font-family:var(--serif);font-size:29px;line-height:1.2;font-weight:400;margin:5px 0 7px;color:#302C26}
.left-sub{font-family:var(--serif);font-size:13px;color:#827666;margin:0 0 23px}
.section-label{font-size:9px;letter-spacing:.17em;color:#A07852;text-transform:uppercase;margin-bottom:10px}
.chapter-list{list-style:none;padding:0;margin:0 0 22px;border-top:1px solid #D4C8B6}
.chapter-list li{border-bottom:1px solid #D4C8B6}
.chapter-list button{background:none;border:0;width:100%;display:flex;align-items:center;gap:12px;text-align:left;padding:11px 5px;color:#766E62;font-family:var(--serif);font-size:13px}
.chapter-list button span{font-family:var(--sans);font-size:9px;color:#A99C8B;letter-spacing:.1em}
.chapter-list button.active{color:var(--terracotta);padding-left:10px;border-left:2px solid var(--terracotta)}
.chapter-list button:hover{color:var(--terracotta)}
.left-lower{border-top:1px solid #D4C8B6;padding-top:18px}
.context-row{display:flex;align-items:center;gap:10px;margin:12px 0}
.avatar{width:36px;height:36px;border-radius:50%;border:1px solid #BEAC93;display:grid;place-items:center;background:#D8C9B5;color:#66513B;font-family:var(--serif);font-size:16px;flex:none}
.context-row strong{display:block;font-family:var(--serif);font-weight:400;font-size:14px}
.context-row small{display:block;color:#938777;font-size:9px;margin-top:3px;letter-spacing:.05em}
.context-note{margin:15px 0 0;padding:11px 13px;border-left:2px solid var(--brass);background:#E6DDCF;color:#746B5E;font-family:var(--serif);font-size:12px;line-height:1.65}
.writer-head{display:flex;justify-content:space-between;align-items:flex-start;gap:16px;margin-bottom:20px}
.writer-title{font-family:var(--serif);font-size:31px;font-weight:400;margin:0 0 7px;line-height:1.2;color:#2E2A25}
.writer-meta{color:#918575;font-size:9px;letter-spacing:.1em}
.writer-tools{display:flex;gap:7px;flex-wrap:wrap;justify-content:flex-end}
.tool-btn{display:inline-flex;align-items:center;gap:6px;padding:9px 11px;border:1px solid #D1C4B1;background:#F7F2E9;color:#5B554C;border-radius:3px;font-size:10px;white-space:nowrap}
.tool-btn:hover{border-color:#A98C66;background:#ECE2D3}
.tool-btn.primary{background:var(--terracotta);border-color:#914232;color:#F7EEE2}
.tool-btn.primary:hover{background:#934333}
.tool-btn svg{width:14px;height:14px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.editor-shell{height:calc(100% - 105px);min-height:430px;position:relative;overflow:hidden}
.manuscript{height:100%;overflow:hidden;font-family:var(--serif);font-size:17px;line-height:2.05;color:#342F28;outline:none;white-space:pre-wrap;overflow-wrap:break-word;caret-color:var(--terracotta);}
.manuscript p{margin:0 0 15px;text-indent:2em}
.page-manuscript{height:calc(100% - 175px);overflow:hidden;padding-top:8px}
.manuscript:empty:before{content:attr(data-placeholder);color:#B2A695}
.manuscript[contenteditable="false"]{user-select:text}
.page-number{position:absolute;bottom:18px;left:0;right:0;text-align:center;font-family:var(--serif);font-size:10px;color:#A99D8B;letter-spacing:.15em}
.edit-status{position:absolute;right:48px;bottom:18px;color:#A99D8B;font-size:9px;letter-spacing:.06em}
.inspire-note{font-family:var(--serif);font-size:13px;color:#857969;line-height:1.7;margin-top:10px}
.turn-controls{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:10px auto 0;max-width:1500px;color:#B7AA98;font-size:10px;letter-spacing:.08em}
.turn-controls button{border:0;color:#E4D6C2;background:transparent;padding:8px 10px;font-size:11px}
.turn-controls button:hover{color:#D7B98E}
.turn-controls button:disabled{opacity:.25;cursor:default}
/* page turn overlay */
.turn-leaf{position:absolute;z-index:10;top:0;bottom:0;width:50%;background:var(--paper);border:1px solid #D3C6B4;display:none;backface-visibility:hidden;transform-style:preserve-3d;box-shadow:0 4px 15px rgba(67,48,29,.18)}
.turn-leaf.next{right:0;transform-origin:left center}
.turn-leaf.prev{left:0;transform-origin:right center}
.turn-leaf.animate-next{display:block;animation:leafNext .55s ease-in-out forwards}
.turn-leaf.animate-prev{display:block;animation:leafPrev .55s ease-in-out forwards}
@keyframes leafNext{from{transform:rotateY(0deg)}to{transform:rotateY(-180deg)}}
@keyframes leafPrev{from{transform:rotateY(0deg)}to{transform:rotateY(180deg)}}
/* dialogs */
.scrim{position:fixed;inset:0;z-index:40;background:rgba(24,20,16,.55);display:none;align-items:center;justify-content:center;padding:20px}
.scrim.show{display:flex}
.dialog{width:min(560px,100%);background:var(--paper);border:1px solid #C9BBA7;box-shadow:0 24px 60px rgba(0,0,0,.32);padding:26px 28px 24px;border-radius:3px;position:relative}
.dialog:before{content:"";position:absolute;inset:8px;border:1px solid #D8CCBA;pointer-events:none}
.dialog-head{display:flex;justify-content:space-between;align-items:flex-start;position:relative;z-index:1}
.dialog-kicker{color:#A07852;font-size:9px;letter-spacing:.2em;text-transform:uppercase}
.dialog h2{font-family:var(--serif);font-size:27px;font-weight:400;margin:7px 0 6px}
.dialog p{font-family:var(--serif);font-size:14px;line-height:1.7;color:#766D60;margin:7px 0 15px;position:relative;z-index:1}
.close-dialog{border:0;background:none;color:#7D7366;font-size:20px;position:relative;z-index:1}
.prompt-box{position:relative;z-index:1;border:1px solid #D0C3B0;background:#F8F4EC;padding:14px 15px;font-family:var(--serif);font-size:14px;line-height:1.8;color:#464037;margin:13px 0}
.idea-list{position:relative;z-index:1;display:grid;gap:8px;margin:15px 0}
.idea{border:1px solid #D7CBB9;background:#F8F4EC;padding:11px 13px;text-align:left;color:#5C544A;font-family:var(--serif);font-size:13px;line-height:1.6}
.idea.selected{border-color:var(--terracotta);background:#EFE2D7}
.idea p{margin:0 0 .65em}.idea p:last-child{margin-bottom:0}.idea h1,.idea h2,.idea h3{margin:.2em 0 .5em;font-size:15px}
.dialog-actions{display:flex;justify-content:flex-end;gap:8px;position:relative;z-index:1;margin-top:17px}
.dialog-actions button{padding:10px 15px;border:1px solid #CDBFAE;background:transparent;color:#5C544A;font-size:11px;border-radius:2px}
.dialog-actions .confirm{background:var(--terracotta);color:#F8F0E5;border-color:#914232}
.dialog textarea{position:relative;z-index:1;width:100%;min-height:76px;border:1px solid #D0C3B0;background:#F8F4EC;padding:12px;font:13px/1.6 var(--serif);color:#403A32;resize:vertical}
.toast{position:fixed;z-index:60;left:50%;bottom:26px;transform:translateX(-50%) translateY(15px);background:#252522;color:#F2EDE3;border:1px solid #8E7961;padding:11px 16px;font-size:11px;opacity:0;transition:all .25s;pointer-events:none}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
@media(max-width:950px){.shelf{grid-template-columns:repeat(2,minmax(190px,1fr));gap:30px}.book-object{height:330px}.book-pages-edge{height:310px}.open-book{height:auto;min-height:0;grid-template-columns:1fr;filter:none}.page.left{display:none}.spine{display:none}.page.right{min-height:calc(100vh - 150px);border-radius:8px;padding:28px 28px 34px;box-shadow:0 10px 22px rgba(0,0,0,.2)}.editor-shell{height:calc(100vh - 330px)}.studio{padding:14px}.turn-leaf{width:100%}}
@media(max-width:600px){.bookshelf{padding:22px 18px 40px}.brandbar{margin-bottom:42px}.shelf-intro{align-items:flex-start;flex-direction:column}.shelf{grid-template-columns:1fr 1fr;gap:24px 15px}.book-object{height:250px}.book-pages-edge{height:238px;width:15px}.book-cover{right:11px}.cover-content{padding:29px 18px 20px 28px}.cover-title{font-size:22px}.cover-emblem{margin:16px 0 12px;width:34px;height:34px}.cover-bottom{font-size:7px}.book-meta{font-size:12px;gap:8px}.book-meta small{font-size:8px}.shelf-caption{margin-top:34px}.studio-head{margin-bottom:10px}.studio-world{display:none}.head-btn{font-size:9px;padding:7px}.writer-head{flex-direction:column}.writer-tools{justify-content:flex-start}.writer-title{font-size:27px}.page.right{padding:24px 22px 34px}.manuscript{font-size:16px;line-height:1.9}.editor-shell{height:calc(100vh - 390px);min-height:260px}.dialog{padding:22px 20px}.top-note{display:none}}
</style>
</head>
<body>
<div class="app">
  <section class="bookshelf" id="bookshelf">
    <header class="brandbar">
      <div class="brand"><div class="brand-mark">K</div><div>KHALA STUDIO<small>THE LIVING ATELIER</small></div></div>
      <div class="top-note">A QUIET PLACE FOR IMAGINATION</div>
    </header>
    <div class="shelf-intro">
      <div><div class="kicker">YOUR CREATIVE LIBRARY</div><h1>每一本书，都是一个世界。</h1><p>在这里，打开你的下一个创造。</p></div>
      <button class="new-book" id="newBook">＋　创建 Workplace</button>
    </div>
    <div class="shelf">
      <article class="book-card" data-book="moon" style="--cover:#713D3B;--cover-edge:#512C2A;--foil:#C9A77F;--cover-text:#F0E1CF">
        <div class="book-object"><div class="book-pages-edge"></div><div class="book-cover"><div class="book-spine"></div><div class="cover-content"><div class="cover-sub">KHALA　·　VOL. 01</div><div class="cover-rule"></div><div class="cover-emblem">✦</div><h2 class="cover-title">Velvet<br>Moon</h2><div class="cover-sub">A WORLD OF STORIES</div><div class="cover-rule"></div><div class="cover-bottom">FICTION · 12 CHAPTERS</div></div></div></div>
        <div class="book-meta"><span>绒月之境</span><small>小说 · 12 章</small></div>
      </article>
      <article class="book-card" data-book="garden" style="--cover:#354B40;--cover-edge:#26382F;--foil:#C6B58D;--cover-text:#E8E5D5">
        <div class="book-object"><div class="book-pages-edge"></div><div class="book-cover"><div class="book-spine"></div><div class="cover-content"><div class="cover-sub">KHALA　·　VOL. 02</div><div class="cover-rule"></div><div class="cover-emblem">❧</div><h2 class="cover-title">Little<br>Garden</h2><div class="cover-sub">CHARACTER ARCHIVE</div><div class="cover-rule"></div><div class="cover-bottom">ORIGINAL IP · 8 CHARACTERS</div></div></div></div>
        <div class="book-meta"><span>小小花园</span><small>原创 IP · 8 个角色</small></div>
      </article>
      <article class="book-card" data-book="blue" style="--cover:#34404C;--cover-edge:#27323D;--foil:#BFB18D;--cover-text:#E8E6DD">
        <div class="book-object"><div class="book-pages-edge"></div><div class="book-cover"><div class="book-spine"></div><div class="cover-content"><div class="cover-sub">KHALA　·　VOL. 03</div><div class="cover-rule"></div><div class="cover-emblem">◈</div><h2 class="cover-title">Blue<br>Hour</h2><div class="cover-sub">A VISUAL JOURNEY</div><div class="cover-rule"></div><div class="cover-bottom">FILM CONCEPT · 4 SCENES</div></div></div></div>
        <div class="book-meta"><span>蓝色时刻</span><small>视觉企划 · 4 个场景</small></div>
      </article>
    </div>
    <footer class="shelf-caption"><span>KH​​ALA STUDIO　/　THE BOOKSHELF</span><span>MAKE A WORLD OF YOUR OWN</span></footer>
  </section>

  <section class="opening" id="opening" aria-hidden="true">
    <div class="opening-book">
      <div class="opening-pages"></div>
      <div class="opening-cover" id="openingCover"><div class="cover-content"><div class="cover-sub">KHALA　·　VOL. 01</div><div class="cover-rule"></div><div class="cover-emblem">✦</div><h2 class="cover-title" id="openingTitle">Velvet Moon</h2><div class="cover-sub">A WORLD OF STORIES</div></div></div>
    </div>
    <div class="opening-caption">正在翻开你的世界……</div>
  </section>

  <section class="studio" id="studio">
    <header class="studio-head">
      <div class="studio-brand"><div class="brand-mark">K</div><span>KHALA STUDIO</span></div>
      <div class="studio-world" id="studioWorld">Velvet Moon　/　The Manuscript</div>
      <div class="head-actions"><button class="head-btn" id="contentsBtn">目录</button><button class="head-btn" id="modeToggle">阅读模式</button><button class="head-btn" id="closeBook">合上书本</button></div>
    </header>
    <main class="open-book" id="openBook">
      <section class="page left" id="leftPage">
        <div class="page-head"><span>CHAPTER 01　·　MANUSCRIPT</span><strong>THE STORY</strong></div>
        <div class="section-label">VELVET MOON　/　CHAPTER 01</div>
        <h2 class="left-heading">雾中的灯塔</h2>
        <p class="left-sub">每一个故事，都从一个尚未回答的问题开始。</p>
        <div class="manuscript page-manuscript" id="leftManuscript" contenteditable="true" spellcheck="false">
          <p>那天夜里，雾比往常来得更早。</p>
          <p>港口的钟敲过九下，街道上的煤气灯一盏接一盏地暗了下去。艾琳站在旧工厂的门口，听见海浪拍打堤岸的声音。她已经十年没有回来过这里。</p>
          <p>她记得父亲总说，灯塔从不替任何人指路。它只是让迷路的人知道，远处还有陆地。</p>
        </div>
        <div class="page-number" id="leftPageNumber">— 026 —</div>
      </section>
      <section class="page right" id="rightPage">
        <div class="page-head"><span>CHAPTER 01　·　DRAFT V3</span><strong id="savedStatus">已保存</strong></div>
        <div class="writer-head">
          <div><div class="section-label">THE STORY CONTINUES</div><h1 class="writer-title" id="chapterTitle">雾中的灯塔</h1><div class="writer-meta">字数 <span id="wordCount">186</span>　·　写作中</div></div>
          <div class="writer-tools">
            <button class="tool-btn" id="inspireBtn"><svg viewBox="0 0 24 24"><path d="M9 18h6M10 22h4M8.5 14.5a6 6 0 1 1 7 0c-.8.6-1.2 1.4-1.4 2.5H9.9c-.2-1.1-.6-1.9-1.4-2.5Z"/><path d="M12 2v2M4.9 4.9l1.4 1.4M19.1 4.9l-1.4 1.4"/></svg>给我灵感</button>
            <button class="tool-btn primary" id="continueBtn"><svg viewBox="0 0 24 24"><path d="M5 19c4-1 6-4 7-8 1 4 3 7 7 8M12 11V3M8 7l4-4 4 4"/></svg>AI 续写</button>
          </div>
        </div>
        <div class="editor-shell"><div class="manuscript" id="manuscript" contenteditable="true" spellcheck="false" data-placeholder="从这里开始写下你的故事……"><p>海风从窗缝里灌进来。远处的灯塔闪烁着，像是有什么东西正在回应她。</p><p>艾琳把铜色护目镜推到额头上，借着工作台那盏快要熄灭的煤油灯，重新检查手中的图纸。纸张边缘已经发脆，父亲的字迹却仍然清晰。</p><p>“如果你读到这里，说明我没能亲自把它交给你。”</p><p>她停下了动作。工厂深处传来一声轻响，像有什么金属物件掉在了地上。</p></div></div>
        <div class="page-number" id="rightPageNumber">— 027 —</div><div class="edit-status" id="editStatus">点击纸面即可编辑</div>
      </section>
      <div class="spine"></div>
      <div class="turn-leaf next" id="turnLeaf"></div>
    </main>
    <div class="turn-controls"><button id="prevPage" disabled>←　上一页</button><span id="spreadLabel">第 27–28 页　/　阅读与创作</span><button id="nextPage">下一页　→</button></div>
  </section>

  <div class="scrim" id="contentsDialog">
    <section class="dialog" role="dialog" aria-modal="true" aria-labelledby="contentsTitle">
      <div class="dialog-head"><div><div class="dialog-kicker">THE TABLE OF CONTENTS</div><h2 id="contentsTitle">章节目录</h2></div><button class="close-dialog" data-close="contentsDialog" aria-label="关闭">×</button></div>
      <p>像翻阅一本书一样，选择你要进入的章节。</p>
      <ul class="chapter-list" id="chapterList" style="position:relative;z-index:1;margin-bottom:0">
        <li><button class="active" data-chapter="0"><span>01</span> 雾中的灯塔</button></li>
        <li><button data-chapter="1"><span>02</span> 铜色的回声</button></li>
        <li><button data-chapter="2"><span>03</span> 没有寄出的信</button></li>
        <li><button data-chapter="3"><span>04</span> 深夜来客</button></li>
      </ul>
    </section>
  </div>

  <div class="scrim" id="inspireDialog">
    <section class="dialog" role="dialog" aria-modal="true" aria-labelledby="inspireTitle">
      <div class="dialog-head"><div><div class="dialog-kicker">A MOMENT OF INSPIRATION</div><h2 id="inspireTitle">给我一点灵感</h2></div><button class="close-dialog" data-close="inspireDialog" aria-label="关闭">×</button></div>
      <p>不替你写作，只提供几个可以继续探索的方向。选择一个，或者把它当作新的思考起点。</p>
      <div class="idea-list" id="ideaList">
        <button class="idea selected">让工厂里的金属声成为某种暗号，艾琳意识到有人比她更早到达。</button>
        <button class="idea">让父亲的图纸缺少关键一页，而那一页正被罗温藏着。</button>
        <button class="idea">让艾琳发现灯塔的闪烁频率与图纸上的机械结构完全一致。</button>
      </div>
      <div class="dialog-actions"><button data-close="inspireDialog">先不采用</button><button class="confirm" id="useIdea">作为写作提示</button></div>
    </section>
  </div>

  <div class="scrim" id="continueDialog">
    <section class="dialog" role="dialog" aria-modal="true" aria-labelledby="continueTitle">
      <div class="dialog-head"><div><div class="dialog-kicker">CONTINUE THE MANUSCRIPT</div><h2 id="continueTitle">AI 续写预览</h2></div><button class="close-dialog" data-close="continueDialog" aria-label="关闭">×</button></div>
      <p>根据当前章节、人物设定和故事情境，从光标位置继续。生成内容先放在这里，确认后才写入正文。</p>
      <div class="prompt-box" id="generatedText">门后的脚步声停住了。艾琳没有回头，只将图纸慢慢折起，藏进外套内侧。她认得那种沉默——罗温每次准备说谎之前，都会先安静下来。</div>
      <div class="dialog-actions"><button id="regenerate">重新生成</button><button data-close="continueDialog">放弃</button><button class="confirm" id="acceptContinuation">插入正文</button></div>
    </section>
  </div>
  <div class="toast" id="toast">已保存</div>
</div>
<script type="text/plain" id="studio-prototype-legacy">
const books={
 moon:{title:'Velvet Moon',name:'绒月之境',cover:'#713D3B',foil:'#C9A77F',subtitle:'A WORLD OF STORIES',chapter:'雾中的灯塔',chapterNo:'01',pages:27},
 garden:{title:'Little Garden',name:'小小花园',cover:'#354B40',foil:'#C6B58D',subtitle:'CHARACTER ARCHIVE',chapter:'角色档案',chapterNo:'PROFILE',pages:1},
 blue:{title:'Blue Hour',name:'蓝色时刻',cover:'#34404C',foil:'#BFB18D',subtitle:'A VISUAL JOURNEY',chapter:'场景与分镜',chapterNo:'SCENE 01',pages:1}
};
let currentBook='moon',mode='write',pageNo=26,selectedIdea=0,currentSpread=0;
const manuscriptSpreads=[
 {left:`<p>那天夜里，雾比往常来得更早。</p><p>港口的钟敲过九下，街道上的煤气灯一盏接一盏地暗了下去。艾琳站在旧工厂的门口，听见海浪拍打堤岸的声音。她已经十年没有回来过这里。</p><p>她记得父亲总说，灯塔从不替任何人指路。它只是让迷路的人知道，远处还有陆地。</p>`,right:`<p>海风从窗缝里灌进来。远处的灯塔闪烁着，像是有什么东西正在回应她。</p><p>艾琳把铜色护目镜推到额头上，借着工作台那盏快要熄灭的煤油灯，重新检查手中的图纸。纸张边缘已经发脆，父亲的字迹却仍然清晰。</p><p>“如果你读到这里，说明我没能亲自把它交给你。”</p><p>她停下了动作。工厂深处传来一声轻响，像有什么金属物件掉在了地上。</p>`},
 {left:`<p>她把图纸翻到背面。那里有一行很淡的铅笔字，几乎被潮气完全抹去。</p><p>“不要相信钟声。真正的门，在灯熄灭之后。”</p><p>艾琳抬起头。远处的灯塔正好闪烁了第三次。</p>`,right:`<p>门后的脚步声停住了。</p><p>艾琳没有回头，只将图纸慢慢折起，藏进外套内侧。她认得那种沉默——罗温每次准备说谎之前，都会先安静下来。</p><p>“你迟到了十年。”她说。</p><p>身后的人没有回答。只有一枚旧怀表，在黑暗中轻轻走动。</p>`},
 {left:`<p>罗温终于走进灯下。他的外套沾着雨水，右手却干燥得反常，像是一路都把它藏在怀里。</p><p>“我不是来解释的。”他说，“我是来阻止你打开那扇门。”</p>`,right:`<p>艾琳看着他，忽然发现自己已经不再害怕。十年前她等过一个答案，十年后她只想知道答案究竟值不值得。</p><p>她把护目镜重新戴好，朝工厂深处走去。</p><p>这一次，罗温没有拦她。</p>`}
];

const bookshelf=document.getElementById('bookshelf'),opening=document.getElementById('opening'),studio=document.getElementById('studio');
const toastEl=document.getElementById('toast');
function showToast(msg){toastEl.textContent=msg;toastEl.classList.add('show');setTimeout(()=>toastEl.classList.remove('show'),1800)}
function openBook(key){currentBook=key;studio.style.display='block';const b=books[key];document.documentElement.style.setProperty('--cover-active',b.cover);document.documentElement.style.setProperty('--foil-active',b.foil);document.getElementById('openingTitle').textContent=b.title;document.getElementById('studioWorld').textContent=b.title+'　/　'+(key==='moon'?'The Manuscript':key==='garden'?'Character Archive':'Visual Journey');opening.classList.add('active');opening.setAttribute('aria-hidden','false');bookshelf.style.opacity='0';bookshelf.style.transform='scale(.985)';setTimeout(()=>{opening.classList.remove('active');opening.setAttribute('aria-hidden','true');opening.style.display='none';studio.classList.add('active');requestAnimationFrame(()=>studio.classList.add('visible'));},1750)}
document.querySelectorAll('.book-card').forEach(card=>card.addEventListener('click',()=>{opening.style.display='grid';void opening.offsetWidth;openBook(card.dataset.book)}));
document.getElementById('newBook').addEventListener('click',()=>showToast('新建 Workplace 原型入口'));
document.getElementById('closeBook').addEventListener('click',()=>{studio.classList.remove('visible');setTimeout(()=>{studio.classList.remove('active');studio.style.display='none';bookshelf.style.opacity='1';bookshelf.style.transform='scale(1)';showToast('已回到创作书架');},550)});
function saveCurrentSpread(){manuscriptSpreads[currentSpread].left=document.getElementById('leftManuscript').innerHTML;manuscriptSpreads[currentSpread].right=document.getElementById('manuscript').innerHTML}
function updatePageMeta(){document.getElementById('leftPageNumber').textContent='— '+String(pageNo).padStart(3,'0')+' —';document.getElementById('rightPageNumber').textContent='— '+String(pageNo+1).padStart(3,'0')+' —';document.getElementById('spreadLabel').textContent='第 '+pageNo+'–'+(pageNo+1)+' 页　/　阅读与创作';document.getElementById('prevPage').disabled=currentSpread===0;document.getElementById('nextPage').disabled=currentSpread===manuscriptSpreads.length-1}
function renderSpread(){const spread=manuscriptSpreads[currentSpread];document.getElementById('leftManuscript').innerHTML=spread.left;document.getElementById('manuscript').innerHTML=spread.right;pageNo=26+currentSpread*2;updatePageMeta();updateWordCount()}
function updateWordCount(){const text=(document.getElementById('leftManuscript').innerText+' '+document.getElementById('manuscript').innerText).replace(/\s/g,'');document.getElementById('wordCount').textContent=text.length}
function setMode(){mode=mode==='write'?'read':'write';document.getElementById('leftManuscript').contentEditable=mode==='write'?'true':'false';document.getElementById('manuscript').contentEditable=mode==='write'?'true':'false';document.getElementById('modeToggle').textContent=mode==='write'?'阅读模式':'写作模式';document.getElementById('editStatus').textContent=mode==='write'?'点击纸面即可编辑':'阅读中 · 正文只读';document.getElementById('inspireBtn').style.display=mode==='write'?'inline-flex':'none';document.getElementById('continueBtn').style.display=mode==='write'?'inline-flex':'none';showToast(mode==='write'?'已进入写作模式':'已进入阅读模式')}
document.getElementById('modeToggle').addEventListener('click',setMode);
function flowOverflow(id){const source=document.getElementById(id);if(source.innerText.length<760)return;let targetSpread=currentSpread,targetId;if(id==='leftManuscript')targetId='manuscript';else{targetSpread=currentSpread+1;if(!manuscriptSpreads[targetSpread])manuscriptSpreads.push({left:'',right:''});targetId='left'}const holder=document.createElement('div');holder.innerHTML=source.innerHTML;let moved=false;while(holder.innerText.length>650&&holder.children.length>1){const last=holder.lastElementChild;const nextHtml=last.outerHTML;last.remove();if(targetId==='manuscript'){document.getElementById('manuscript').insertAdjacentHTML('beforeend',nextHtml);moved=true}else if(targetId==='left'){manuscriptSpreads[targetSpread].left+=nextHtml;moved=true}}if(moved){source.innerHTML=holder.innerHTML;saveCurrentSpread();showToast('本页已满，文字自然流入下一页');if(targetId==='left'){setTimeout(()=>{turn('next');setTimeout(()=>{const next=document.getElementById('leftManuscript');next.focus();const range=document.createRange();range.selectNodeContents(next);range.collapse(false);const sel=window.getSelection();sel.removeAllRanges();sel.addRange(range)},600)},160)}else{const next=document.getElementById('manuscript');next.focus();const range=document.createRange();range.selectNodeContents(next);range.collapse(false);const sel=window.getSelection();sel.removeAllRanges();sel.addRange(range)}}}
['leftManuscript','manuscript'].forEach(id=>document.getElementById(id).addEventListener('input',()=>{saveCurrentSpread();updateWordCount();flowOverflow(id);document.getElementById('savedStatus').textContent='正在保存…';setTimeout(()=>document.getElementById('savedStatus').textContent='已保存',700)}));
function turn(direction){if((direction==='next'&&currentSpread>=manuscriptSpreads.length-1)||(direction==='prev'&&currentSpread<=0))return;saveCurrentSpread();const leaf=document.getElementById('turnLeaf');leaf.className='turn-leaf '+(direction==='next'?'next animate-next':'prev animate-prev');document.getElementById('prevPage').disabled=true;document.getElementById('nextPage').disabled=true;setTimeout(()=>{currentSpread+=(direction==='next'?1:-1);renderSpread();leaf.className='turn-leaf '+(direction==='next'?'next':'prev');showToast(direction==='next'?'翻到下一页':'翻回上一页');},560)}
document.getElementById('nextPage').addEventListener('click',()=>turn('next'));document.getElementById('prevPage').addEventListener('click',()=>turn('prev'));
document.getElementById('contentsBtn').addEventListener('click',()=>openDialog('contentsDialog'));
document.querySelectorAll('#chapterList button').forEach(btn=>btn.addEventListener('click',()=>{document.querySelectorAll('#chapterList button').forEach(x=>x.classList.remove('active'));btn.classList.add('active');const titles=['雾中的灯塔','铜色的回声','没有寄出的信','深夜来客'];const n=Number(btn.dataset.chapter);document.getElementById('chapterTitle').textContent=titles[n];document.querySelectorAll('.page-head span').forEach(el=>el.textContent='CHAPTER '+String(n+1).padStart(2,'0')+'　·　MANUSCRIPT');closeDialog('contentsDialog');currentSpread=0;renderSpread();showToast('已打开 '+titles[n])}));
const editor=document.getElementById('manuscript');let activeEditorId='manuscript';
['leftManuscript','manuscript'].forEach(id=>document.getElementById(id).addEventListener('focus',()=>{activeEditorId=id}));
function openDialog(id){document.getElementById(id).classList.add('show')};function closeDialog(id){document.getElementById(id).classList.remove('show')}
document.querySelectorAll('[data-close]').forEach(btn=>btn.addEventListener('click',()=>closeDialog(btn.dataset.close)));
document.querySelectorAll('.scrim').forEach(s=>s.addEventListener('click',e=>{if(e.target===s)s.classList.remove('show')}));
document.getElementById('inspireBtn').addEventListener('click',()=>openDialog('inspireDialog'));
document.querySelectorAll('.idea').forEach((idea,i)=>idea.addEventListener('click',()=>{document.querySelectorAll('.idea').forEach(x=>x.classList.remove('selected'));idea.classList.add('selected');selectedIdea=i}));
document.getElementById('useIdea').addEventListener('click',()=>{const idea=document.querySelectorAll('.idea')[selectedIdea].textContent;closeDialog('inspireDialog');showToast('灵感已加入本章写作提示：'+idea.slice(0,16)+'…')});
document.getElementById('continueBtn').addEventListener('click',()=>openDialog('continueDialog'));
document.getElementById('regenerate').addEventListener('click',()=>{document.getElementById('generatedText').textContent='远处的灯塔忽然熄灭。黑暗落下来的瞬间，艾琳听见身后有人轻轻说出了她父亲的名字。她终于明白，这张图纸并不是留给她的遗物，而是一封迟到了十年的邀请。';showToast('已生成另一种续写方向')});
document.getElementById('acceptContinuation').addEventListener('click',()=>{const block=document.getElementById('generatedText').textContent;const p=document.createElement('p');p.textContent=block;const selection=window.getSelection();const leftEditor=document.getElementById('leftManuscript');const target=selection&&selection.rangeCount&&leftEditor.contains(selection.anchorNode)?leftEditor:selection&&selection.rangeCount&&editor.contains(selection.anchorNode)?editor:document.getElementById(activeEditorId);if(selection&&selection.rangeCount&&(leftEditor.contains(selection.anchorNode)||editor.contains(selection.anchorNode))){const range=selection.getRangeAt(0);range.collapse(false);range.insertNode(p)}else target.appendChild(p);saveCurrentSpread();closeDialog('continueDialog');updateWordCount();showToast('续写内容已插入正文')});
// keyboard page turning, but never intercept while typing in the manuscript
window.addEventListener('keydown',e=>{if(e.target===editor||e.target===document.getElementById('leftManuscript'))return;if(e.key==='ArrowRight'&&studio.classList.contains('visible'))turn('next');if(e.key==='ArrowLeft'&&studio.classList.contains('visible'))turn('prev');if(e.key==='Escape'){document.querySelectorAll('.scrim.show').forEach(s=>s.classList.remove('show'))}});
</script>
<script>
(() => {
  'use strict';

  const API = '/studio/api/v1';
  const INITIAL_CONTENT = `# 雾中的灯塔

那天夜里，雾比往常来得更早。

港口的钟敲过九下，街道上的煤气灯一盏接一盏地暗了下去。艾琳站在旧工厂的门口，听见海浪拍打堤岸的声音。她已经十年没有回来过这里。

她记得父亲总说，灯塔从不替任何人指路。它只是让迷路的人知道，远处还有陆地。

海风从窗缝里灌进来。远处的灯塔闪烁着，像是有什么东西正在回应她。`;
  const palette = [
    ['#713D3B', '#27323D', '#C9A77F'],
    ['#354B40', '#24332C', '#C6B58D'],
    ['#34404C', '#27323D', '#BFB18D']
  ];

  const state = {
    capabilities: null,
    model: null,
    workplace: null,
    workplaces: [],
    documents: [],
    document: null,
    revision: null,
    savedContent: '',
    conflict: false,
    saveTimer: null,
    savePromise: null,
    continuation: '',
    continueAbort: null,
    inspiration: ''
  };

  const bookshelf = document.getElementById('bookshelf');
  const opening = document.getElementById('opening');
  const studio = document.getElementById('studio');
  const leftEditor = document.getElementById('leftManuscript');
  const rightEditor = document.getElementById('manuscript');
  const toastEl = document.getElementById('toast');
  const savedStatus = document.getElementById('savedStatus');

  let manuscriptSpreads = [{ left: '', right: '' }];
  let currentSpread = 0;
  let pageNo = 26;
  let mode = 'write';
  let activeEditorId = 'manuscript';

  class ApiError extends Error {
    constructor(status, payload) {
      const error = (payload && payload.error) || {};
      super(error.message || `HTTP ${status}`);
      this.status = status;
      this.code = error.code || 'REQUEST_FAILED';
      this.payload = payload || {};
      this.currentRevision = error.current_revision;
    }
  }

  async function api(path, options = {}) {
    const response = await fetch(API + path, {
      method: options.method || 'GET',
      headers: options.body ? { 'Content-Type': 'application/json' } : {},
      body: options.body ? JSON.stringify(options.body) : undefined,
      signal: options.signal
    });
    let payload = null;
    try { payload = await response.json(); } catch (_) { payload = null; }
    if (!response.ok) throw new ApiError(response.status, payload);
    return payload ? payload.data : null;
  }

  function showToast(message) {
    toastEl.textContent = message;
    toastEl.classList.add('show');
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => toastEl.classList.remove('show'), 2200);
  }

  function setSaveStatus(text) { savedStatus.textContent = text; }

  function escapeHtml(text) {
    return String(text == null ? '' : text)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function inlineMarkdown(text) {
    return escapeHtml(text)
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>');
  }

  function markdownToHtml(markdown) {
    const normalized = String(markdown || '').replace(/\r\n/g, '\n');
    const chunks = normalized.split(/\n{2,}/).map((part) => part.trim()).filter(Boolean);
    if (!chunks.length) return '<p><br></p>';
    return chunks.map((chunk) => {
      const heading = /^(#{1,6})\s+(.*)$/.exec(chunk);
      if (heading) return `<h${heading[1].length}>${inlineMarkdown(heading[2])}</h${heading[1].length}>`;
      const lines = chunk.split('\n');
      if (lines.every((line) => /^[-*]\s+/.test(line))) {
        return `<ul>${lines.map((line) => `<li>${inlineMarkdown(line.replace(/^[-*]\s+/, ''))}</li>`).join('')}</ul>`;
      }
      return `<p>${lines.map(inlineMarkdown).join('<br>')}</p>`;
    }).join('');
  }

  function htmlToMarkdown(html) {
    const holder = document.createElement('div');
    holder.innerHTML = html || '';
    const blocks = Array.from(holder.children).map((element) => {
      const text = (element.innerText || element.textContent || '').replace(/\u00a0/g, ' ').trim();
      if (!text) return '';
      const tag = element.tagName.toLowerCase();
      if (/^h[1-6]$/.test(tag)) return `${'#'.repeat(Number(tag[1]))} ${text}`;
      if (tag === 'li') return `- ${text}`;
      if (tag === 'ul' || tag === 'ol') {
        return Array.from(element.querySelectorAll('li'))
          .map((item) => `- ${(item.innerText || '').trim()}`).filter(Boolean).join('\n');
      }
      return text;
    });
    if (blocks.length) return blocks.filter(Boolean).join('\n\n');
    return (holder.innerText || holder.textContent || '').trim();
  }

  function plainLength(html) {
    const holder = document.createElement('div');
    holder.innerHTML = html || '';
    return (holder.innerText || '').length;
  }

  function paginate(html) {
    const holder = document.createElement('div');
    holder.innerHTML = html || '<p><br></p>';
    const blocks = Array.from(holder.children);
    if (!blocks.length) return ['<p><br></p>'];
    const pages = [];
    let page = '';
    let length = 0;
    blocks.forEach((block) => {
      const blockLength = (block.innerText || '').length;
      if (page && length + blockLength > 620) {
        pages.push(page);
        page = '';
        length = 0;
      }
      page += block.outerHTML;
      length += blockLength;
    });
    if (page) pages.push(page);
    return pages;
  }

  function setManuscriptFromMarkdown(markdown) {
    const pages = paginate(markdownToHtml(markdown));
    manuscriptSpreads = [];
    for (let index = 0; index < pages.length; index += 2) {
      manuscriptSpreads.push({ left: pages[index] || '', right: pages[index + 1] || '' });
    }
    if (!manuscriptSpreads.length) manuscriptSpreads.push({ left: '', right: '' });
    currentSpread = 0;
  }

  function saveCurrentSpread() {
    if (!manuscriptSpreads[currentSpread]) manuscriptSpreads[currentSpread] = { left: '', right: '' };
    manuscriptSpreads[currentSpread].left = leftEditor.innerHTML;
    manuscriptSpreads[currentSpread].right = rightEditor.innerHTML;
  }

  function documentMarkdown() {
    saveCurrentSpread();
    return manuscriptSpreads
      .flatMap((spread) => [htmlToMarkdown(spread.left), htmlToMarkdown(spread.right)])
      .filter(Boolean).join('\n\n');
  }

  function renderSpread() {
    const spread = manuscriptSpreads[currentSpread] || { left: '', right: '' };
    leftEditor.innerHTML = spread.left;
    rightEditor.innerHTML = spread.right;
    pageNo = 26 + currentSpread * 2;
    updatePageMeta();
    updateWordCount();
  }

  function updatePageMeta() {
    document.getElementById('leftPageNumber').textContent = `— ${String(pageNo).padStart(3, '0')} —`;
    document.getElementById('rightPageNumber').textContent = `— ${String(pageNo + 1).padStart(3, '0')} —`;
    document.getElementById('spreadLabel').textContent = `第 ${pageNo}–${pageNo + 1} 页　/　阅读与创作`;
    document.getElementById('prevPage').disabled = currentSpread === 0;
    document.getElementById('nextPage').disabled = currentSpread === manuscriptSpreads.length - 1;
  }

  function updateWordCount() {
    const text = `${leftEditor.innerText} ${rightEditor.innerText}`.replace(/\s/g, '');
    document.getElementById('wordCount').textContent = text.length;
    document.getElementById('chapterTitle').textContent = state.document ? state.document.title : '未命名手稿';
  }

  function turn(direction) {
    if ((direction === 'next' && currentSpread >= manuscriptSpreads.length - 1) ||
        (direction === 'prev' && currentSpread <= 0)) return;
    saveCurrentSpread();
    const leaf = document.getElementById('turnLeaf');
    leaf.className = `turn-leaf ${direction === 'next' ? 'next animate-next' : 'prev animate-prev'}`;
    document.getElementById('prevPage').disabled = true;
    document.getElementById('nextPage').disabled = true;
    setTimeout(() => {
      currentSpread += direction === 'next' ? 1 : -1;
      renderSpread();
      leaf.className = `turn-leaf ${direction === 'next' ? 'next' : 'prev'}`;
    }, 560);
  }

  function flowOverflow(id) {
    const source = document.getElementById(id);
    if (!source || source.innerText.length < 760) return;
    let targetSpread = currentSpread;
    let targetId;
    if (id === 'leftManuscript') {
      targetId = 'manuscript';
    } else {
      targetSpread = currentSpread + 1;
      if (!manuscriptSpreads[targetSpread]) manuscriptSpreads.push({ left: '', right: '' });
      targetId = 'left';
    }
    const holder = document.createElement('div');
    holder.innerHTML = source.innerHTML;
    let moved = false;
    while (holder.innerText.length > 650 && holder.children.length > 1) {
      const last = holder.lastElementChild;
      const nextHtml = last.outerHTML;
      last.remove();
      if (targetId === 'manuscript') {
        rightEditor.insertAdjacentHTML('beforeend', nextHtml);
        moved = true;
      } else {
        manuscriptSpreads[targetSpread].left += nextHtml;
        moved = true;
      }
    }
    if (moved) {
      source.innerHTML = holder.innerHTML;
      saveCurrentSpread();
      scheduleSave();
      if (targetId === 'left') {
        setTimeout(() => turn('next'), 120);
      }
    }
  }

  async function saveDocumentNow() {
    clearTimeout(state.saveTimer);
    state.saveTimer = null;
    if (state.savePromise) return state.savePromise;
    if (!state.workplace || !state.document || state.conflict) return;
    saveCurrentSpread();
    const content = documentMarkdown();
    if (content === state.savedContent) { setSaveStatus('已保存'); return; }
    setSaveStatus('正在保存…');
    const promise = (async () => {
      try {
        const updated = await api(`/workplaces/${state.workplace.id}/documents/${state.document.id}`, {
          method: 'PUT',
          body: {
            title: state.document.title,
            content,
            content_format: 'markdown',
            expected_revision: state.revision
          }
        });
        state.document = updated;
        state.revision = updated.revision;
        state.savedContent = updated.content;
        setSaveStatus('已保存');
      } catch (error) {
        if (error.status === 409) {
          state.conflict = true;
          setSaveStatus('版本冲突');
          showToast('正文已在别处更新；这里不会覆盖较新的版本。请重新打开文档。');
        } else {
          setSaveStatus('保存失败');
          showToast(error.message || '保存失败');
        }
      }
    })();
    state.savePromise = promise;
    try { await promise; } finally {
      if (state.savePromise === promise) state.savePromise = null;
    }
  }

  function scheduleSave() {
    if (!state.document) return;
    if (state.conflict) { setSaveStatus('版本冲突'); return; }
    setSaveStatus('正在保存…');
    clearTimeout(state.saveTimer);
    state.saveTimer = setTimeout(saveDocumentNow, 700);
  }

  async function flushSave() {
    clearTimeout(state.saveTimer);
    state.saveTimer = null;
    await saveDocumentNow();
  }

  function renderBookshelf() {
    const shelf = bookshelf.querySelector('.shelf');
    if (!state.workplaces.length) {
      shelf.innerHTML = '<p style="grid-column:1/-1;color:#B7AA98;font-family:var(--serif)">还没有 Workplace。点击“新建 Workplace”开始。</p>';
      return;
    }
    shelf.innerHTML = state.workplaces.map((workplace, index) => {
      const colors = palette[index % palette.length];
      return `<article class="book-card" data-book="${escapeHtml(workplace.id)}" style="--cover:${escapeHtml(workplace.cover_color || colors[0])};--cover-edge:${colors[1]};--foil:${colors[2]};--cover-text:#E8E6DD">
        <div class="book-object"><div class="book-pages-edge"></div><div class="book-cover"><div class="book-spine"></div><div class="cover-content"><div class="cover-sub">KHALA　·　STUDIO</div><div class="cover-rule"></div><div class="cover-emblem">✦</div><h2 class="cover-title">${escapeHtml(workplace.title)}</h2><div class="cover-sub">${escapeHtml(workplace.description || 'A WORLD OF STORIES')}</div><div class="cover-rule"></div><div class="cover-bottom">${workplace.document_count} DOCUMENTS</div></div></div></div>
        <div class="book-meta"><span>${escapeHtml(workplace.title)}</span><small>${workplace.document_count} 篇文档</small></div>
      </article>`;
    }).join('');
  }

  function documentDepth(documentEntry) {
    let depth = 0;
    let parent = documentEntry.parent_id;
    const byId = new Map(state.documents.map((item) => [item.id, item]));
    while (parent && depth < 8) {
      depth += 1;
      const entry = byId.get(parent);
      parent = entry ? entry.parent_id : null;
    }
    return depth;
  }

  function renderChapterList() {
    const list = document.getElementById('chapterList');
    if (!state.documents.length) {
      list.innerHTML = '<li style="color:#77716A">这份 Workplace 暂时没有文档。</li>';
      return;
    }
    list.innerHTML = state.documents.map((entry, index) => {
      const active = state.document && state.document.id === entry.id ? ' active' : '';
      const label = entry.kind === 'manuscript' ? 'M' : String(index + 1).padStart(2, '0');
      return `<li style="padding-left:${documentDepth(entry) * 18}px"><button data-document="${escapeHtml(entry.id)}" class="${active}"><span>${escapeHtml(label)}</span> ${escapeHtml(entry.title)}</button></li>`;
    }).join('');
  }

  async function loadDocument(documentId) {
    const entry = state.documents.find((item) => item.id === documentId);
    if (!entry) return;
    const documentData = await api(`/workplaces/${state.workplace.id}/documents/${documentId}`);
    state.document = documentData;
    state.revision = documentData.revision;
    state.savedContent = documentData.content;
    state.conflict = false;
    setManuscriptFromMarkdown(documentData.content);
    renderSpread();
    renderChapterList();
    setSaveStatus('已保存');
    document.getElementById('chapterTitle').textContent = documentData.title;
    document.getElementById('leftPage').querySelector('.left-heading').textContent = documentData.title;
    document.getElementById('studioWorld').textContent = `${state.workplace.title}　/　${documentData.title}`;
  }

  async function selectDocument(documentId) {
    if (state.document && state.document.id === documentId) {
      closeDialog('contentsDialog');
      return;
    }
    await flushSave();
    await loadDocument(documentId);
    closeDialog('contentsDialog');
    showToast('已打开文档');
  }

  async function openWorkplace(workplaceId) {
    const workplace = state.workplaces.find((item) => item.id === workplaceId);
    if (!workplace) return;
    await flushSave();
    state.workplace = workplace;
    studio.style.display = 'block';
    document.documentElement.style.setProperty('--cover-active', workplace.cover_color);
    document.documentElement.style.setProperty('--foil-active', '#C9A77F');
    document.getElementById('openingTitle').textContent = workplace.title;
    opening.classList.add('active');
    opening.setAttribute('aria-hidden', 'false');
    opening.style.display = 'grid';
    bookshelf.style.opacity = '0';
    bookshelf.style.transform = 'scale(.985)';
    const started = Date.now();
    try {
      state.documents = await api(`/workplaces/${workplace.id}/documents`);
      let documentEntry = state.documents.find((entry) => entry.kind === 'manuscript') ||
        state.documents.find((entry) => entry.kind === 'chapter') || state.documents[0];
      if (!documentEntry) {
        documentEntry = await api(`/workplaces/${workplace.id}/documents`, {
          method: 'POST',
          body: {
            parent_id: null,
            kind: 'manuscript',
            title: workplace.title,
            content_format: 'markdown',
            content: INITIAL_CONTENT,
            sort_order: 0
          }
        });
        state.documents = [documentEntry];
      }
      await loadDocument(documentEntry.id);
    } catch (error) {
      showToast(error.message || '无法打开 Workplace');
    }
    const wait = Math.max(0, 1250 - (Date.now() - started));
    setTimeout(() => {
      opening.classList.remove('active');
      opening.setAttribute('aria-hidden', 'true');
      opening.style.display = 'none';
      studio.classList.add('active');
      requestAnimationFrame(() => studio.classList.add('visible'));
    }, wait);
  }

  async function createWorkplace() {
    const title = window.prompt('Workplace 名称', 'Untitled World');
    if (!title || !title.trim()) return;
    try {
      const created = await api('/workplaces', {
        method: 'POST',
        body: { title: title.trim(), description: '', cover_color: palette[state.workplaces.length % palette.length][0] }
      });
      state.workplaces = await api('/workplaces');
      renderBookshelf();
      showToast('已创建 Workplace');
      await openWorkplace(created.id);
    } catch (error) {
      showToast(error.message || '创建 Workplace 失败');
    }
  }

  function activeEditor() {
    return document.getElementById(activeEditorId) || rightEditor;
  }

  function selectionContext() {
    const editor = activeEditor();
    const selection = window.getSelection();
    if (!selection || !selection.rangeCount || !editor.contains(selection.anchorNode)) {
      return { selected_text: '', context_before: editor.innerText || '', context_after: '' };
    }
    const range = selection.getRangeAt(0);
    const before = document.createRange();
    before.selectNodeContents(editor);
    before.setEnd(range.startContainer, range.startOffset);
    const after = document.createRange();
    after.selectNodeContents(editor);
    after.setStart(range.endContainer, range.endOffset);
    return {
      selected_text: selection.toString(),
      context_before: before.toString(),
      context_after: after.toString()
    };
  }

  async function requestInspiration() {
    if (!state.document) { showToast('请先打开一份文档'); return; }
    openDialog('inspireDialog');
    const list = document.getElementById('ideaList');
    list.innerHTML = '<div class="idea selected">正在阅读上下文并寻找方向…</div>';
    state.inspiration = '';
    try {
      const request = selectionContext();
      request.instruction = 'Give me several distinct ways to develop this scene.';
      if (state.model) request.model = state.model;
      const result = await api(`/workplaces/${state.workplace.id}/documents/${state.document.id}/ai/inspire`, {
        method: 'POST', body: request
      });
      state.inspiration = result.content || '';
      list.innerHTML = `<div class="idea selected">${markdownToHtml(state.inspiration)}</div>`;
    } catch (error) {
      list.innerHTML = `<div class="idea">${escapeHtml(error.message || '获取灵感失败')}</div>`;
    }
  }

  function parseEventBlock(block) {
    let event = 'message';
    const data = [];
    block.split(/\r?\n/).forEach((line) => {
      if (line.startsWith('event:')) event = line.slice(6).trim();
      else if (line.startsWith('data:')) data.push(line.slice(5).trimStart());
    });
    return { event, data: data.join('\n') };
  }

  async function consumeEvents(response, onEvent) {
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let boundary;
      while ((boundary = buffer.indexOf('\n\n')) >= 0) {
        const block = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        if (block.trim()) onEvent(parseEventBlock(block));
      }
    }
  }

  async function startContinuation() {
    if (!state.document) { showToast('请先打开一份文档'); return; }
    if (state.continueAbort) state.continueAbort.abort();
    const controller = new AbortController();
    state.continueAbort = controller;
    state.continuation = '';
    const output = document.getElementById('generatedText');
    output.textContent = '正在续写…';
    setSaveStatus('AI 生成中');
    try {
      const request = selectionContext();
      request.instruction = 'Continue this scene naturally from the cursor.';
      request.max_tokens = 1024;
      if (state.model) request.model = state.model;
      const response = await fetch(`${API}/workplaces/${state.workplace.id}/documents/${state.document.id}/ai/continue`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
        signal: controller.signal
      });
      if (!response.ok) {
        let payload = null;
        try { payload = await response.json(); } catch (_) {}
        throw new ApiError(response.status, payload);
      }
      output.textContent = '';
      await consumeEvents(response, (message) => {
        if (message.event === 'token') {
          const token = JSON.parse(message.data).text || '';
          state.continuation += token;
          output.textContent = state.continuation;
        } else if (message.event === 'error') {
          const failure = JSON.parse(message.data);
          throw new Error(failure.message || '生成失败');
        }
      });
      setSaveStatus('已保存');
      if (!state.continuation) output.textContent = '没有生成可插入的内容。';
    } catch (error) {
      if (error.name === 'AbortError') return;
      output.textContent = error.message || '生成失败';
      setSaveStatus('已保存');
    } finally {
      if (state.continueAbort === controller) state.continueAbort = null;
    }
  }

  function insertContinuation() {
    if (!state.continuation.trim()) { showToast('还没有可插入的续写内容'); return; }
    if (state.conflict) { showToast('版本冲突，请重新打开文档后再插入'); return; }
    const editor = activeEditor();
    const selection = window.getSelection();
    const paragraph = document.createElement('p');
    paragraph.textContent = state.continuation.trim();
    if (selection && selection.rangeCount && editor.contains(selection.anchorNode)) {
      const range = selection.getRangeAt(0);
      range.deleteContents();
      range.insertNode(paragraph);
    } else {
      editor.appendChild(paragraph);
    }
    saveCurrentSpread();
    updateWordCount();
    scheduleSave();
    closeDialog('continueDialog');
    showToast('续写内容已插入正文');
  }

  function openDialog(id) { document.getElementById(id).classList.add('show'); }
  function closeDialog(id) {
    document.getElementById(id).classList.remove('show');
    if (id === 'continueDialog' && state.continueAbort) {
      state.continueAbort.abort();
      state.continueAbort = null;
      setSaveStatus('已保存');
    }
  }

  function setMode() {
    mode = mode === 'write' ? 'read' : 'write';
    leftEditor.contentEditable = mode === 'write' ? 'true' : 'false';
    rightEditor.contentEditable = mode === 'write' ? 'true' : 'false';
    document.getElementById('modeToggle').textContent = mode === 'write' ? '阅读模式' : '写作模式';
    document.getElementById('editStatus').textContent = mode === 'write' ? '点击纸面即可编辑' : '阅读中 · 正文只读';
    document.getElementById('inspireBtn').style.display = mode === 'write' ? 'inline-flex' : 'none';
    document.getElementById('continueBtn').style.display = mode === 'write' ? 'inline-flex' : 'none';
  }

  async function bootstrap() {
    try {
      state.capabilities = await api('/capabilities');
      state.model = state.capabilities.default_model || null;
      state.workplaces = await api('/workplaces');
      if (!state.workplaces.length) {
        await api('/workplaces', {
          method: 'POST',
          body: { title: 'Velvet Moon', description: 'A world between the pages.', cover_color: '#713D3B' }
        });
        state.workplaces = await api('/workplaces');
      }
      renderBookshelf();
    } catch (error) {
      console.error(error);
      showToast('Studio API 暂不可用');
    }
  }

  bookshelf.querySelector('.shelf').addEventListener('click', (event) => {
    const card = event.target.closest('.book-card');
    if (card) openWorkplace(card.dataset.book);
  });
  document.getElementById('newBook').addEventListener('click', createWorkplace);
  document.getElementById('closeBook').addEventListener('click', async () => {
    await flushSave();
    studio.classList.remove('visible');
    setTimeout(() => {
      studio.classList.remove('active');
      studio.style.display = 'none';
      bookshelf.style.opacity = '1';
      bookshelf.style.transform = 'scale(1)';
      api('/workplaces').then((workplaces) => {
        state.workplaces = workplaces;
        renderBookshelf();
      }).catch(() => {});
    }, 550);
  });
  document.getElementById('nextPage').addEventListener('click', () => turn('next'));
  document.getElementById('prevPage').addEventListener('click', () => turn('prev'));
  document.getElementById('contentsBtn').addEventListener('click', () => openDialog('contentsDialog'));
  document.getElementById('chapterList').addEventListener('click', (event) => {
    const button = event.target.closest('button[data-document]');
    if (button) selectDocument(button.dataset.document);
  });
  document.getElementById('inspireBtn').addEventListener('click', requestInspiration);
  document.getElementById('continueBtn').addEventListener('click', () => {
    openDialog('continueDialog');
    startContinuation();
  });
  document.getElementById('regenerate').addEventListener('click', startContinuation);
  document.getElementById('acceptContinuation').addEventListener('click', insertContinuation);
  document.getElementById('useIdea').addEventListener('click', () => {
    if (!state.inspiration) return;
    closeDialog('inspireDialog');
    showToast('灵感已保留为写作提示');
  });
  document.getElementById('modeToggle').addEventListener('click', setMode);
  document.querySelectorAll('[data-close]').forEach((button) => {
    button.addEventListener('click', () => closeDialog(button.dataset.close));
  });
  document.querySelectorAll('.scrim').forEach((scrim) => {
    scrim.addEventListener('click', (event) => {
      if (event.target === scrim) closeDialog(scrim.id);
    });
  });
  [leftEditor, rightEditor].forEach((editor) => {
    editor.addEventListener('focus', () => { activeEditorId = editor.id; });
    editor.addEventListener('input', () => {
      saveCurrentSpread();
      updateWordCount();
      flowOverflow(editor.id);
      scheduleSave();
    });
  });
  window.addEventListener('keydown', (event) => {
    if (event.target === leftEditor || event.target === rightEditor) return;
    if (event.key === 'ArrowRight' && studio.classList.contains('visible')) turn('next');
    if (event.key === 'ArrowLeft' && studio.classList.contains('visible')) turn('prev');
    if (event.key === 'Escape') document.querySelectorAll('.scrim.show').forEach((scrim) => closeDialog(scrim.id));
  });
  window.addEventListener('beforeunload', () => {
    if (state.saveTimer) {
      clearTimeout(state.saveTimer);
      saveDocumentNow();
    }
  });

  bootstrap();
})();
</script>
</body>
</html>
