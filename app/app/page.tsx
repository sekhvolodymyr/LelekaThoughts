import {HomeEntry} from '@/components/leleka/home-entry';
import {LogoMark} from '@/components/leleka/logo-mark';
import './home.css';

const origin='https://lelekathoughts.vercel.app';
const structuredData={
 '@context':'https://schema.org','@graph':[
  {'@type':'WebSite','@id':`${origin}/#website`,url:`${origin}/`,name:'LelekaThoughts',alternateName:['Лелека','Leleka Thoughts'],inLanguage:'uk',description:'Українська соцмережа для креаторів та їхніх спільнот.'},
  {'@type':'Organization','@id':`${origin}/#organization`,name:'LelekaThoughts',alternateName:'Лелека',url:`${origin}/`,logo:{'@type':'ImageObject',url:`${origin}/icon-512.png`,width:512,height:512}},
 ],
};

export default function Home(){return <>
 <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(structuredData).replace(/</g,'\\u003c')}}/>
 <HomeEntry><div className="home-page">
  <header className="home-header"><a className="home-brand" href="/" aria-label="LelekaThoughts — головна"><LogoMark/><span>LelekaThoughts</span></a><a className="home-login" href="/#/feed">Увійти до спільноти <span aria-hidden="true">↗</span></a></header>
  <main id="home-main">
   <section className="home-hero" aria-labelledby="home-title">
    <p className="home-eyebrow">ІДЕЇ, ЩО ПРОДОВЖУЮТЬСЯ</p>
    <h1 id="home-title">Українська соцмережа,<br/>де ідеї <em>ростуть разом.</em></h1>
    <p className="home-intro">LelekaThoughts («Лелека») — простір для креаторів і людей, яким цікаво, як народжується нове. Ділися задумом, показуй творчий процес і розвивай ідеї разом зі своєю аудиторією.</p>
    <div className="home-actions"><a className="home-primary" href="/#/feed">Відкрити LelekaThoughts <span aria-hidden="true">↗</span></a><a className="home-secondary" href="#how-it-works">Як це працює <span aria-hidden="true">↓</span></a></div>
    <p className="home-note">Публічний контент можна читати без реєстрації. Спільнота від 16 років.</p>
   </section>
   <section className="home-process" id="how-it-works" aria-labelledby="process-title">
    <div className="home-section-heading"><p className="home-eyebrow">ВІД ПЕРШОЇ ДУМКИ ДО СПІЛЬНОЇ ІСТОРІЇ</p><h2 id="process-title">Творчість — це процес.<br/>Дай іншим стати його частиною.</h2></div>
    <div className="home-steps">
     <article><span className="home-step-number">01 / ЗАДУМ</span><h3>Почни з поста</h3><p>Поділися думкою, ескізом, фотографією чи музичним задумом. Короткий пост із текстом і фото — простий спосіб розпочати розмову.</p></article>
     <article><span className="home-step-number">02 / ПРОДОВЖЕННЯ</span><h3>Розвивай ланцюжок</h3><p>Додавай нові частини до власного поста. Читачі зможуть простежити шлях від першої ідеї до результату та обговорити кожен етап.</p></article>
     <article><span className="home-step-number">03 / ПРОЦЕС</span><h3>Показуй у сторіс</h3><p>Ділися фото й короткими відео. Зберігай важливі моменти в іменовані серії та прив’язуй їх до ланцюжка, щоб історія залишалася цілісною.</p></article>
    </div>
   </section>
   <section className="home-community" aria-labelledby="community-title"><div><p className="home-eyebrow">ЗНАЙДИ СВОЇХ</p><h2 id="community-title">Твоя ідея.<br/>Твоя спільнота.</h2></div><div><p>Музика, дизайн, фото, письмо, розробка чи мистецтво — у LelekaThoughts є місце для різних творчих напрямів. Обирай інтереси, знаходь авторів і стеж за їхніми роботами у стрічці.</p><p>Долучайся через коментарі, відповіді, вподобайки й репости. Для особистої розмови є повідомлення: взаємні підписки спілкуються одразу, інші починають із запиту.</p><a className="home-text-link" href="/#/search">Знайти креаторів <span aria-hidden="true">↗</span></a></div></section>
   <section className="home-faq" aria-labelledby="faq-title"><h2 id="faq-title">Познайомся з «Лелекою»</h2>
    <details><summary>Що таке LelekaThoughts?</summary><p>LelekaThoughts, або «Лелека», — українська соцмережа для публікації ідей і творчого процесу. Пости, авторські ланцюжки та серії сторіс допомагають розповідати історію поступово й отримувати відгук аудиторії.</p></details>
    <details><summary>Чи можна користуватися з телефона?</summary><p>Так. Сайт адаптується до телефона, а PWA можна додати на головний екран. Для роботи потрібен інтернет. Інтерфейс доступний українською та англійською.</p></details>
    <details><summary>Чим ланцюжок відрізняється від серії сторіс?</summary><p>Ланцюжок — послідовність постів, яку продовжує автор. Серія — постійна іменована добірка сторіс. Їх можна зв’язати: читати розвиток ідеї в постах і дивитися процес у сторіс.</p></details>
   </section>
  </main>
  <footer className="home-footer"><span>LelekaThoughts · Лелека</span><span>Українська соцмережа для креаторів</span><a href="/#/feed">До стрічки ↗</a></footer>
 </div></HomeEntry>
 </>}
