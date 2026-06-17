const admin = require('./node_modules/firebase-admin');
const Anthropic = require('../functions/node_modules/@anthropic-ai/sdk');
require('dotenv').config({ path: './functions/.env' });

admin.initializeApp({ credential: admin.credential.cert(require('../serviceAccountKey.json')) });
const db = admin.firestore();
const client = new Anthropic.default({ apiKey: process.env.ANTHROPIC_API_KEY });

// Must match PASSAGE_ROTATION in functions/src/index.ts
const PASSAGE_ROTATION = [
  { id: 'jhn_3_16',   ref: 'John 3:16',           text: 'For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.' },
  { id: 'rom_8_28',   ref: 'Romans 8:28',          text: 'And we know that in all things God works for the good of those who love him, who have been called according to his purpose.' },
  { id: 'php_4_13',   ref: 'Philippians 4:13',     text: 'I can do all this through him who gives me strength.' },
  { id: 'jer_29_11',  ref: 'Jeremiah 29:11',       text: 'For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.' },
  { id: 'psa_23_1',   ref: 'Psalm 23:1',           text: 'The Lord is my shepherd, I lack nothing.' },
  { id: 'pro_3_5',    ref: 'Proverbs 3:5',         text: 'Trust in the Lord with all your heart and lean not on your own understanding.' },
  { id: 'isa_40_31',  ref: 'Isaiah 40:31',         text: 'But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.' },
  { id: 'mat_6_33',   ref: 'Matthew 6:33',         text: 'But seek first his kingdom and his righteousness, and all these things will be given to you as well.' },
  { id: 'rom_8_38',   ref: 'Romans 8:38-39',       text: 'For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God that is in Christ Jesus our Lord.' },
  { id: 'php_4_6',    ref: 'Philippians 4:6-7',    text: 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.' },
  { id: 'gal_2_20',   ref: 'Galatians 2:20',       text: 'I have been crucified with Christ and I no longer live, but Christ lives in me. The life I now live in the body, I live by faith in the Son of God, who loved me and gave himself for me.' },
  { id: 'psa_46_10',  ref: 'Psalm 46:10',          text: "He says, 'Be still, and know that I am God; I will be exalted among the nations, I will be exalted in the earth.'" },
  { id: 'mat_11_28',  ref: 'Matthew 11:28-30',     text: 'Come to me, all you who are weary and burdened, and I will give you rest. Take my yoke upon you and learn from me, for I am gentle and humble in heart, and you will find rest for your souls. For my yoke is easy and my burden is light.' },
  { id: 'jhn_14_6',   ref: 'John 14:6',            text: "Jesus answered, 'I am the way and the truth and the life. No one comes to the Father except through me.'" },
  { id: 'rom_12_2',   ref: 'Romans 12:2',          text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind. Then you will be able to test and approve what God's will is—his good, pleasing and perfect will." },
  { id: 'eph_2_8',    ref: 'Ephesians 2:8-9',      text: 'For it is by grace you have been saved, through faith—and this is not from yourselves, it is the gift of God—not by works, so that no one can boast.' },
  { id: 'psa_139_14', ref: 'Psalm 139:14',         text: 'I praise you because I am fearfully and wonderfully made; your works are wonderful, I know that full well.' },
  { id: 'isa_41_10',  ref: 'Isaiah 41:10',         text: 'So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand.' },
  { id: 'jhn_1_1',    ref: 'John 1:1',             text: 'In the beginning was the Word, and the Word was with God, and the Word was God.' },
  { id: '1co_13_4',   ref: '1 Corinthians 13:4-7', text: 'Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs. Love does not delight in evil but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres.' },
  { id: 'psa_119_105',ref: 'Psalm 119:105',        text: 'Your word is a lamp for my feet, a light on my path.' },
  { id: 'mat_28_19',  ref: 'Matthew 28:19-20',     text: 'Therefore go and make disciples of all nations, baptizing them in the name of the Father and of the Son and of the Holy Spirit, and teaching them to obey everything I have commanded you. And surely I am with you always, to the very end of the age.' },
  { id: 'rom_5_8',    ref: 'Romans 5:8',           text: 'But God demonstrates his own love for us in this: While we were still sinners, Christ died for us.' },
  { id: '2co_5_17',   ref: '2 Corinthians 5:17',   text: 'Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!' },
  { id: 'eph_6_10',   ref: 'Ephesians 6:10-11',    text: "Finally, be strong in the Lord and in his mighty power. Put on the full armor of God, so that you can take your stand against the devil's schemes." },
  { id: 'heb_11_1',   ref: 'Hebrews 11:1',         text: 'Now faith is confidence in what we hope for and assurance about what we do not see.' },
  { id: 'jas_1_2',    ref: 'James 1:2-4',          text: 'Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds, because you know that the testing of your faith produces perseverance. Let perseverance finish its work so that you may be mature and complete, not lacking anything.' },
  { id: '1pe_5_7',    ref: '1 Peter 5:7',          text: 'Cast all your anxiety on him because he cares for you.' },
  { id: '1jn_4_19',   ref: '1 John 4:19',          text: 'We love because he first loved us.' },
  { id: 'psa_27_1',   ref: 'Psalm 27:1',           text: 'The Lord is my light and my salvation—whom shall I fear? The Lord is the stronghold of my life—of whom shall I be afraid?' },
  { id: 'luk_1_37',   ref: 'Luke 1:37',            text: 'For no word from God will ever fail.' },
  { id: 'rom_8_1',    ref: 'Romans 8:1',           text: 'Therefore, there is now no condemnation for those who are in Christ Jesus.' },
  { id: 'psa_34_18',  ref: 'Psalm 34:18',          text: 'The Lord is close to the brokenhearted and saves those who are crushed in spirit.' },
  { id: 'isa_53_5',   ref: 'Isaiah 53:5',          text: 'But he was pierced for our transgressions, he was crushed for our iniquities; the punishment that brought us peace was on him, and by his wounds we are healed.' },
  { id: 'col_3_23',   ref: 'Colossians 3:23-24',   text: 'Whatever you do, work at it with all your heart, as working for the Lord, not for human masters, since you know that you will receive an inheritance from the Lord as a reward. It is the Lord Christ you are serving.' },
  { id: 'jhn_10_10',  ref: 'John 10:10',           text: 'The thief comes only to steal and kill and destroy; I have come that they may have life, and have it to the full.' },
  { id: 'mat_5_14',   ref: 'Matthew 5:14-16',      text: 'You are the light of the world. A town built on a hill cannot be hidden. Neither do people light a lamp and put it under a bowl. Instead they put it on its stand, and it gives light to everyone in the house. In the same way, let your light shine before others, that they may see your good deeds and glorify your Father in heaven.' },
  { id: 'php_1_6',    ref: 'Philippians 1:6',      text: 'Being confident of this, that he who began a good work in you will carry it on to completion until the day of Christ Jesus.' },
  { id: '2ti_1_7',    ref: '2 Timothy 1:7',        text: 'For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline.' },
  { id: 'psa_37_4',   ref: 'Psalm 37:4',           text: 'Take delight in the Lord, and he will give you the desires of your heart.' },
  { id: 'rom_15_13',  ref: 'Romans 15:13',         text: 'May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.' },
  { id: 'heb_12_1',   ref: 'Hebrews 12:1-2',       text: 'Therefore, since we are surrounded by such a great cloud of witnesses, let us throw off everything that hinders and the sin that so easily entangles. And let us run with perseverance the race marked out for us, fixing our eyes on Jesus, the pioneer and perfecter of faith.' },
  { id: 'lam_3_22',   ref: 'Lamentations 3:22-23', text: "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness." },
  { id: 'gal_5_22',   ref: 'Galatians 5:22-23',    text: 'But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control. Against such things there is no law.' },
  { id: 'jhn_15_5',   ref: 'John 15:5',            text: 'I am the vine; you are the branches. If you remain in me and I in you, you will bear much fruit; apart from me you can do nothing.' },
  { id: 'mat_6_9',    ref: 'Matthew 6:9-13',       text: 'Our Father in heaven, hallowed be your name, your kingdom come, your will be done, on earth as it is in heaven. Give us today our daily bread. And forgive us our debts, as we also have forgiven our debtors. And lead us not into temptation, but deliver us from the evil one.' },
  { id: 'psa_91_1',   ref: 'Psalm 91:1-2',         text: "Whoever dwells in the shelter of the Most High will rest in the shadow of the Almighty. I will say of the Lord, 'He is my refuge and my fortress, my God, in whom I trust.'" },
  { id: 'eph_3_20',   ref: 'Ephesians 3:20-21',    text: 'Now to him who is able to do immeasurably more than all we ask or imagine, according to his power that is at work within us, to him be glory in the church and in Christ Jesus throughout all generations, for ever and ever! Amen.' },
  { id: 'act_1_8',    ref: 'Acts 1:8',             text: 'But you will receive power when the Holy Spirit comes on you; and you will be my witnesses in Jerusalem, and in all Judea and Samaria, and to the ends of the earth.' },
  { id: 'rev_3_20',   ref: 'Revelation 3:20',      text: 'Here I am! I stand at the door and knock. If anyone hears my voice and opens the door, I will come in and eat with that person, and they with me.' },
  { id: 'mic_6_8',    ref: 'Micah 6:8',            text: 'He has shown you, O mortal, what is good. And what does the Lord require of you? To act justly and to love mercy and to walk humbly with your God.' },
  { id: '1co_10_13',  ref: '1 Corinthians 10:13',  text: 'No temptation has overtaken you except what is common to mankind. And God is faithful; he will not let you be tempted beyond what you can bear. But when you are tempted, he will also provide a way out so that you can endure it.' },
  { id: 'deu_31_6',   ref: 'Deuteronomy 31:6',     text: 'Be strong and courageous. Do not be afraid or terrified because of them, for the Lord your God goes with you; he will never leave you nor forsake you.' },
  { id: '2ch_7_14',   ref: '2 Chronicles 7:14',    text: "If my people, who are called by my name, will humble themselves and pray and seek my face and turn from their wicked ways, then I will hear from heaven, and I will forgive their sin and will heal their land." },
  { id: 'psa_1_1',    ref: 'Psalm 1:1-3',          text: "Blessed is the one who does not walk in step with the wicked or stand in the way that sinners take or sit in the company of mockers, but whose delight is in the law of the Lord, and who meditates on his law day and night. That person is like a tree planted by streams of water, which yields its fruit in season and whose leaf does not wither—whatever they do prospers." },
  { id: 'jhn_8_32',   ref: 'John 8:32',            text: 'Then you will know the truth, and the truth will set you free.' },
  { id: 'rom_1_16',   ref: 'Romans 1:16',          text: 'For I am not ashamed of the gospel, because it is the power of God that brings salvation to everyone who believes: first to the Jew, then to the Gentile.' },
];

function getDayOfYear(date) {
  const start = new Date(date.getFullYear(), 0, 0);
  const diff = date - start;
  return Math.floor(diff / (1000 * 60 * 60 * 24));
}

function dateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}

// Seed N days starting from today (default: 7)
const DAYS_AHEAD = parseInt(process.argv[2] || '7', 10);

async function seedDay(date) {
  const key = dateKey(date);
  const dayOfYear = getDayOfYear(date);
  const passage = PASSAGE_ROTATION[dayOfYear % PASSAGE_ROTATION.length];

  console.log(`\n📅 ${key} — ${passage.ref}`);

  // Write manifest so the app knows which passageId to load today
  await db.collection('sparkcache').doc(key).set(
    { passageId: passage.id, reference: passage.ref },
    { merge: true }
  );

  for (const version of ['kjv', 'csb', 'niv']) {
    process.stdout.write(`  ${version}... `);
    try {
      const response = await client.messages.create({
        model: 'claude-haiku-4-5',
        max_tokens: 200,
        messages: [{ role: 'user', content: `Generate one thoughtful reflection question about this verse for a young Christian (16-30): "${passage.ref}: ${passage.text}". Reply with just the question, nothing else.` }]
      });
      const question = response.content[0].text.trim();
      await db.collection('sparkcache').doc(key).collection(passage.id).doc(version).set({
        text: passage.text,
        reference: passage.ref,
        question,
        passageId: passage.id,
        version,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      process.stdout.write('✅ ');
    } catch(e) {
      process.stdout.write(`❌ ${e.message} `);
    }
  }
}

async function seed() {
  console.log(`🔥 Seeding sparkcache for next ${DAYS_AHEAD} days...\n`);
  console.log('Usage: node seed_spark.js [days_ahead]  (default: 7)\n');

  for (let i = 0; i < DAYS_AHEAD; i++) {
    const date = new Date();
    date.setDate(date.getDate() + i);
    await seedDay(date);
  }

  console.log('\n\nDone!');
  process.exit();
}

seed().catch(e => { console.error(e); process.exit(1); });
