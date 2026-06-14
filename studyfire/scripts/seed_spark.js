const admin = require('./node_modules/firebase-admin');
const Anthropic = require('../functions/node_modules/@anthropic-ai/sdk');
require('dotenv').config({ path: '../functions/.env' });

admin.initializeApp({ credential: admin.credential.cert(require('../serviceAccountKey.json')) });
const db = admin.firestore();

const client = new Anthropic.default({ apiKey: process.env.ANTHROPIC_API_KEY });

const passages = [
  { id: 'rom_8_28', ref: 'Romans 8:28', text: 'And we know that in all things God works for the good of those who love him, who have been called according to his purpose.' },
  { id: 'jhn_3_16', ref: 'John 3:16', text: 'For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.' },
  { id: 'psa_23_1', ref: 'Psalm 23:1', text: 'The Lord is my shepherd, I lack nothing.' },
  { id: 'php_4_13', ref: 'Philippians 4:13', text: 'I can do all this through him who gives me strength.' },
  { id: 'jer_29_11', ref: 'Jeremiah 29:11', text: 'For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.' },
];

async function seed() {
  const now = new Date();
  const today = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
  console.log('Seeding sparkcache for:', today);
  for (const p of passages) {
    process.stdout.write(`  ${p.ref}... `);
    try {
      const response = await client.messages.create({
        model: 'claude-haiku-4-5',
        max_tokens: 200,
        messages: [{ role: 'user', content: `Generate one thoughtful reflection question about this verse for a young Christian: "${p.ref}: ${p.text}". Reply with just the question, nothing else.` }]
      });
      const question = response.content[0].text.trim();
      await db.collection('sparkcache').doc(today).collection(p.id).doc('kjv').set({
        text: p.text, reference: p.ref, question, passageId: p.id, version: 'kjv',
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log('done');
    } catch(e) { console.log('FAILED:', e.message); }
  }
  console.log('Complete!');
  process.exit();
}
seed().catch(e => { console.error(e); process.exit(1); });
