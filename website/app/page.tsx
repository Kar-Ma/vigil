const testFlightUrl = "https://testflight.apple.com/join/5E5Cywaw";
const githubUrl = "https://github.com/Kar-Ma/vigil";

function Brand() {
  return <a className="brand" href="#top" aria-label="Vigil home"><img src="/vigil-icon.png" alt="" /><span>VIGIL</span></a>;
}

export default function Home() {
  return <main id="top">
    <nav className="nav shell"><Brand /><div className="nav-links"><a href="#what">What it does</a><a href="#limits">Limits</a><a href="#privacy">Privacy</a></div><a className="nav-button" href={testFlightUrl} target="_blank" rel="noreferrer">Join the beta <span>↗</span></a></nav>

    <section className="hero shell"><div className="hero-copy"><p className="eyebrow">Open-source iOS safety app</p><h1>When a moment<br />matters, <strong>Vigil.</strong></h1><p className="hero-lede">Vigil helps you record important moments quickly, keep completed recordings behind your iPhone’s protections, and create copies in destinations you control.</p><div className="actions"><a className="button button-light" href={testFlightUrl} target="_blank" rel="noreferrer">Join the TestFlight beta <span>↗</span></a><a className="quiet-link" href={githubUrl} target="_blank" rel="noreferrer">View the code <span>↗</span></a></div><p className="note">Early prototype · Initially limited to 50 testers</p></div><div className="hero-icon"><img src="/vigil-icon.png" alt="Vigil app icon" /></div></section>

    <section className="black-band"><div className="shell band-inner"><p>Record with intention.</p><p>Protect what you can.</p><p>Keep control.</p></div></section>

    <section className="section shell" id="what"><div className="section-label">What Vigil does</div><div className="section-content"><h2>A simple camera-first experience for moments that may be hard to explain later.</h2><div className="feature-grid"><article><span>01</span><h3>Record quickly</h3><p>One-tap video and audio recording, with rear, front, and compatible simultaneous front-and-rear modes.</p></article><article><span>02</span><h3>Keep a protected local copy</h3><p>Completed recordings go to the Vigil Vault, behind Face ID or your iPhone passcode and iPhone file protection.</p></article><article><span>03</span><h3>Make copies you control</h3><p>Optionally save to Camera Roll or upload a completed recording directly to a visible Vigil folder in your own Google Drive.</p></article></div></div></section>

    <section className="dark-section" id="how"><div className="shell dark-layout"><div><p className="section-label light">Built for real-world use</p><h2>Useful when<br />things get<br /><strong>complicated.</strong></h2></div><div className="detail-list"><div><span>Screen Curtain</span><p>Hide the live preview and dim the display while recording controls and iOS privacy indicators remain visible.</p></div><div><span>Interruption protection</span><p>When capture is interrupted, Vigil finalizes the active clip when possible and starts a new protected clip when recording resumes.</p></div><div><span>Action Button shortcut</span><p>Assign Start Vigil Recording to a supported iPhone’s Action Button for faster access.</p></div><div><span>SOS handoff</span><p>Passes your configured regional emergency number to the iPhone’s confirmation screen. Vigil is not a replacement for Emergency SOS.</p></div></div></div></section>

    <section className="section shell" id="limits"><div className="section-label">Honest by design</div><div className="section-content"><h2>Vigil is an early prototype—not a finished emergency or evidence-preservation service.</h2><p className="lead">A recording is protected only after iOS finishes writing it. Vigil does not currently upload while recording, guarantee recovery after phone loss, or provide cryptographic proof of authenticity. Local recording laws still apply.</p><div className="limit-grid"><p>Do not rely on Vigil as your only protection.</p><p>Test it on your own physical iPhone before trusting it.</p><p>Read the full privacy and security notes before using the beta.</p></div></div></section>

    <section className="privacy-section" id="privacy"><div className="shell privacy-layout"><div><p className="section-label">Privacy</p><h2>No Vigil account.<br /><strong>No ads.</strong><br />No tracking.</h2></div><div><p className="lead">Vigil does not operate a server for your recordings. Completed recordings stay on your iPhone unless you choose Camera Roll, Google Drive, or another sharing destination.</p><p className="lead">The app requests only the permissions it needs: camera, microphone, optional add-only Photos access, Face ID, and optional Google Drive access using Google’s <code>drive.file</code> scope.</p><div className="link-row"><a href="/privacy" className="button button-light">Read privacy notice <span>↗</span></a><a href="/security" className="quiet-link">Read security notes <span>↗</span></a></div></div></div></section>

    <section className="cta shell"><img src="/vigil-icon.png" alt="" /><div><p className="section-label">Try the early access beta</p><h2>Keep Vigil<br /><strong>close.</strong></h2></div><a className="button button-light" href={testFlightUrl} target="_blank" rel="noreferrer">Join TestFlight <span>↗</span></a></section>

    <footer className="footer shell"><Brand /><p>Vigil is open source and built in public.</p><div><a href={githubUrl} target="_blank" rel="noreferrer">GitHub ↗</a><a href="/privacy">Privacy</a><a href="/security">Security</a></div></footer>
  </main>;
}
