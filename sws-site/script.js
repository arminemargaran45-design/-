(()=>{
  const q=s=>document.querySelector(s);
  const qa=s=>[...document.querySelectorAll(s)];

  document.body.classList.add('sws-motion-ready');

  // Always animate, including phones with reduced-motion enabled in OS/browser.
  const reveals=qa('.reveal');
  reveals.forEach((el,i)=>{
    el.style.transitionDelay=Math.min((i%4)*55,165)+'ms';
  });

  if('IntersectionObserver' in window){
    const io=new IntersectionObserver(entries=>{
      entries.forEach(entry=>{
        if(entry.isIntersecting){
          entry.target.classList.add('visible');
          io.unobserve(entry.target);
        }
      });
    },{threshold:0.06,rootMargin:'0px 0px -4% 0px'});
    reveals.forEach(el=>io.observe(el));
  }else{
    const show=()=>{
      const h=window.innerHeight||document.documentElement.clientHeight;
      reveals.forEach(el=>{
        if(el.getBoundingClientRect().top<h*0.94) el.classList.add('visible');
      });
    };
    addEventListener('scroll',show,{passive:true});
    addEventListener('resize',show,{passive:true});
    show();
  }

  // Prevent a hidden block on browsers that delay IntersectionObserver callbacks.
  setTimeout(()=>{
    reveals.forEach(el=>{
      const r=el.getBoundingClientRect();
      if(r.top<(window.innerHeight||800)*1.05 && r.bottom>-80) el.classList.add('visible');
    });
  },350);

  const light=q('.cursor-light');
  if(light){
    window.addEventListener('pointermove',e=>{
      light.style.left=e.clientX+'px';
      light.style.top=e.clientY+'px';
    },{passive:true});
  }

  const b=q('.hamb'),m=q('.mobile-menu');
  if(b&&m){
    b.setAttribute('aria-label','Открыть меню');
    b.setAttribute('aria-expanded','false');
    b.addEventListener('click',()=>{
      const open=m.classList.toggle('open');
      b.setAttribute('aria-expanded',String(open));
    });
    qa('.mobile-menu a').forEach(a=>a.addEventListener('click',()=>{
      m.classList.remove('open');
      b.setAttribute('aria-expanded','false');
    }));
  }

  // Canonical host: www.stylingwrapstudio.ru is the only public primary URL.
  if(location.hostname==='stylingwrapstudio.ru'){
    location.replace('https://www.stylingwrapstudio.ru'+location.pathname+location.search+location.hash);
    return;
  }

  // Subtle continuous scroll motion on every phone and desktop.
  const heroMedia=q('.hero-media');
  const pageHero=q('.page-hero');
  let ticking=false;
  const motion=()=>{
    ticking=false;
    const y=window.scrollY||0;
    if(heroMedia){
      const shift=Math.min(y*0.035,28);
      heroMedia.style.transform='translate3d(0,'+shift+'px,0) scale(1.04)';
    }
    if(pageHero){
      const shift=Math.min(y*0.02,18);
      pageHero.style.backgroundPosition='center calc(50% + '+shift+'px)';
    }
  };
  addEventListener('scroll',()=>{
    if(!ticking){
      ticking=true;
      requestAnimationFrame(motion);
    }
  },{passive:true});
  motion();
})();