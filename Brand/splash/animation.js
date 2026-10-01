/* Quolio splash. All artwork is embedded; there are no network dependencies. */
(() => {
  'use strict';
  const DURATION = 5.8;
  const COLORS = { paper: '#F9F8F3', kraft: '#BFA78A', ink: '#3C3835' };
  const assets = JSON.parse(document.getElementById('quolio-assets').textContent);
  const canvas = document.getElementById('quolio-canvas');
  const ctx = canvas.getContext('2d', { alpha: true });
  const replay = document.getElementById('replay');
  const clamp = (n, a = 0, b = 1) => Math.max(a, Math.min(b, n));
  const smooth = n => { n = clamp(n); return n * n * (3 - 2 * n); };
  const ease = n => { n = clamp(n); return n < .5 ? 4*n*n*n : 1-Math.pow(-2*n+2,3)/2; };
  const mix = (a,b,n) => a+(b-a)*n;
  const image = async svg => {
    const img = new Image();
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    await img.decode();
    return img;
  };
  const rounded = (x,y,w,h,r,fill,stroke) => {
    ctx.beginPath(); ctx.roundRect(x,y,w,h,r);
    if (fill) { ctx.fillStyle=fill; ctx.fill(); }
    if (stroke) { ctx.strokeStyle=stroke; ctx.lineWidth=.8; ctx.stroke(); }
  };
  function makePaper(back = false, variant = 0) {
    const c=document.createElement('canvas'); c.width=720; c.height=900;
    const g=c.getContext('2d'); g.scale(4,4);
    g.fillStyle=back?'#F1EEE6':COLORS.paper;
    g.beginPath();g.roundRect(0,0,180,225,18);g.fill();
    const gradient=g.createLinearGradient(0,0,180,0);
    gradient.addColorStop(0,'rgba(126,111,87,.12)');
    gradient.addColorStop(.13,'rgba(255,255,255,0)');
    gradient.addColorStop(1,'rgba(126,111,87,.025)');
    g.fillStyle=gradient;g.fill();
    g.lineWidth=.75;g.strokeStyle='#DED9CC';g.lineCap='round';
    for(let y=62;y<200;y+=23){g.beginPath();g.moveTo(28,y);g.lineTo(156,y);g.stroke();}
    g.fillStyle=['#E8CD6870','#A8CBA055','#86BBE04D'][variant%3];
    g.beginPath();g.roundRect(29,39,51+variant*8,6,3);g.fill();
    return c;
  }
  function makeInsideCover() {
    const c=document.createElement('canvas'); c.width=780;c.height=960;
    const g=c.getContext('2d');g.scale(4,4);
    g.fillStyle=COLORS.kraft;g.beginPath();g.roundRect(0,0,195,240,26);g.fill();
    g.fillStyle='#EEE9DD';g.beginPath();g.roundRect(7,8,180,225,20);g.fill();
    return c;
  }
  // Project a paper plane around the spiral binding. A light curl lifts the outer edge.
  function projected(x,y,w,h,angle,originX,originY,curl=0) {
    const bulge=Math.sin(x/w*Math.PI)*curl;
    const z=-Math.sin(angle)*x+bulge;
    const perspective=800/(800-z);
    return { x:originX+Math.cos(angle)*x*perspective,
      y:originY+h/2+(y-h/2)*perspective };
  }
  function sheet(img,w,h,angle,ox,oy,curl=0) {
    if(Math.abs(Math.cos(angle))<.005)return;
    // Vertical texture strips follow the perspective surface without mesh seams.
    if(Math.abs(Math.sin(angle))<.00001){
      ctx.save();ctx.translate(ox,oy);ctx.scale(Math.cos(angle)<0?-1:1,1);
      ctx.drawImage(img,0,0,w,h);ctx.restore();return;
    }
    const strips=512;
    for(let i=0;i<strips;i++){
      const x0=i*w/strips,x1=(i+1)*w/strips,xm=(x0+x1)/2;
      const a=projected(x0,0,w,h,angle,ox,oy,curl);
      const b=projected(x1,0,w,h,angle,ox,oy,curl);
      const top=projected(xm,0,w,h,angle,ox,oy,curl);
      const bottom=projected(xm,h,w,h,angle,ox,oy,curl);
      const left=Math.min(a.x,b.x),width=Math.abs(b.x-a.x);
      ctx.drawImage(img,i*img.width/strips,0,img.width/strips,img.height,
        left-.12,top.y,width+.24,bottom.y-top.y);
    }
  }
  const paper=[makePaper(false,0),makePaper(false,1),makePaper(false,2)];
  const reverse=makePaper(true,0),inside=makeInsideCover();
  let images,raf=0,start=0,playing=false,lastTime=0;
  function draw(t) {
    t=clamp(t,0,DURATION);lastTime=t;
    const W=canvas.width,H=canvas.height;
    ctx.clearRect(0,0,W,H);
    const size=Math.min(W,H),scale=size/500;
    ctx.save();ctx.translate((W-size)/2,(H-size)/2);ctx.scale(scale,scale);
    const appear=smooth(t/.5);
    ctx.globalAlpha=appear;
    const closing=ease((t-3.08)/.88);
    const travel=ease((t-3.05)/1.03);
    const spine=mix(248,153.5,travel),top=mix(110,82,travel);
    const rise=14*(1-appear);
    const bounce=t>3.96&&t<4.56?Math.sin((t-3.96)/.6*Math.PI)*Math.exp(-(t-3.96)*6)*.027:0;
    ctx.translate(250,250+rise);ctx.scale(1+bounce,1+bounce);ctx.translate(-250,-250);
    if(t>=3.96){
      ctx.drawImage(images.notebook,0,0,500,500);
    }else{
      ctx.save();ctx.translate(spine-180,top-90);ctx.drawImage(images.base,0,0,500,500);ctx.restore();
      // Open inside cover, with the binding between the left and right page stacks.
      if(closing===0)sheet(inside,195,240,-Math.PI,spine,top);
      for(let n=3;n>=0;n--){
        rounded(spine+6+n*.6,top+8+n*1.2,180,225,20,'#EAE5D9');
      }
      ctx.drawImage(paper[2],spine+6,top+8,180,225);
      ctx.save();ctx.globalAlpha*=1-smooth(closing*2.1);
      for(let n=3;n>=0;n--)rounded(spine-178-n*.6,top+8+n*1.2,180,225,20,'#EAE5D9');
      ctx.drawImage(paper[0],spine-178,top+8,180,225);ctx.restore();
      const turns=[];
      for(let i=0;i<5;i++){
        const p=clamp((t-(.43+i*.44))/.72);
        if(p>0&&p<1)turns.push({p,i,angle:-Math.PI*ease(p)});
      }
      turns.sort((a,b)=>Math.sin(-a.angle)-Math.sin(-b.angle));
      for(const turn of turns){
        const {p,i,angle}=turn;
        const shade=Math.sin(p*Math.PI)*.12;
        ctx.save();ctx.beginPath();ctx.roundRect(spine+6,top+8,180,225,20);ctx.clip();
        const shadow=ctx.createLinearGradient(spine+6,0,spine+140,0);
        shadow.addColorStop(0,`rgba(76,61,38,${shade})`);shadow.addColorStop(1,'rgba(76,61,38,0)');
        ctx.fillStyle=shadow;ctx.fillRect(spine+6,top+8,180,225);ctx.restore();
        sheet(Math.cos(angle)>0?paper[i%3]:reverse,180,225,angle,spine+6,top+8,Math.sin(p*Math.PI)*17);
      }
      if(closing>0){
        const angle=-Math.PI*(1-closing);
        // The inside pages travel with the cover until its decorated front faces us.
        sheet(Math.cos(angle)<0?inside:images.cover,195,240,angle,spine,top);
      }
      ctx.save();ctx.translate(spine-180,top-90);ctx.drawImage(images.rings,0,0,500,500);ctx.restore();
    }
    ctx.globalAlpha=appear*smooth((t-4.02)/.62);
    ctx.save();ctx.translate(0,10*(1-smooth((t-4.02)/.62)));
    ctx.drawImage(images.wordmark,0,0,500,500);ctx.restore();ctx.restore();
    canvas.dataset.time=t.toFixed(3);
  }
  function stop(){cancelAnimationFrame(raf);playing=false;}
  function play(){
    stop();replay.hidden=true;playing=true;start=performance.now();
    const tick=now=>{
      const t=(now-start)/1000;draw(t);
      if(t<DURATION)raf=requestAnimationFrame(tick);
      else {playing=false;replay.hidden=false;window.dispatchEvent(new CustomEvent('quolio:complete'));}
    };raf=requestAnimationFrame(tick);
  }
  function resize(){
    const bounds=canvas.getBoundingClientRect();
    const dpr=Math.min(devicePixelRatio||1,2);
    canvas.width=Math.max(1,Math.round(bounds.width*dpr));
    canvas.height=Math.max(1,Math.round(bounds.height*dpr));
    if(images)draw(playing?(performance.now()-start)/1000:lastTime);
  }
  window.quolio={duration:DURATION,seek(t){stop();draw(t);},play,resize};
  window.quolio.ready=Promise.all(Object.entries(assets).map(async([k,svg])=>[k,await image(svg)])).then(entries=>{
    images=Object.fromEntries(entries);resize();
    const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
    if(new URLSearchParams(location.search).has('render')){draw(0);}
    else if(reduced){draw(DURATION);replay.hidden=false;window.dispatchEvent(new CustomEvent('quolio:complete'));}
    else play();
    replay.addEventListener('click',play);
    new ResizeObserver(resize).observe(canvas);
    return true;
  });
})();
