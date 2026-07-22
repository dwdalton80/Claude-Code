import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";
import { SignedDataVerifier, Environment } from "@apple/app-store-server-library";
import { generateSparkQuestion } from "./claude/spark_questions";
import { generateAiStudy, StudyContext } from "./claude/ai_study";
import { generateDigDeeperStudy, askDigDeeperQuestion, DigDeeperStudyRequest, DigDeeperStudyResponse } from "./claude/dig_deeper_study";
import { generateQuizBatch, generateWordOfDay } from "./claude/quiz_generation";
import { generateSermonDebrief, suggestSermonTitle, generateNoteDevotional, DebriefContext } from "./claude/sermon_debrief";
import { getClaudeClient, MODELS, StudyLevel, studyLevelInstructions } from "./claude/client";
import { recordStudyActivity, replenishGraceDays } from "./gamification/streak_manager";
import { sm2Update, scoreToGrade } from "./gamification/sm2_algorithm";
import {
  sendStreakReminders,
  sendFocusCompanion,
  sendGroupDigests,
  sendPushNotification,
} from "./notifications/push_notifications";
import { sendDigDeeperMorningReminder } from "./notifications/digdeeper_notifications";

admin.initializeApp();
const db = admin.firestore();

// ── Scheduled: 2am Daily ─────────────────────────────────────────────────────

/**
 * Pre-generates today's Spark question for each active passage.
 * One Claude call per passage, result shared with ALL free users.
 */
export const generateDailySpark = functions.pubsub.schedule("0 2 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Generating daily spark questions");

    const now = new Date();
    const today = dateKey(now);
    const passages = getTodaysPassages(now);

    for (const passage of passages) {
      // Write manifest so the app knows which passageId to load today
      await db.collection("sparkcache").doc(today).set(
        { passageId: passage.id, reference: passage.reference },
        { merge: true }
      );

      for (const version of ["kjv", "csb", "niv"]) {
        try {
          const question = await generateSparkQuestion(
            passage.text,
            passage.reference,
            version
          );

          await db
            .collection("sparkcache")
            .doc(today)
            .collection(passage.id)
            .doc(version)
            .set({ ...question, generatedAt: admin.firestore.FieldValue.serverTimestamp() });
        } catch (err) {
          functions.logger.error(`Spark generation failed: ${passage.reference} ${version}`, err);
        }
      }
    }
  });

/**
 * Pre-generates daily quiz questions and Word of the Day via Batch API.
 * 50% cost savings vs individual API calls.
 */
// ── Curated rotating verse list ───────────────────────────────────────────────
const _FOCUS_VERSES: { text: string; reference: string }[] = [
  { text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.", reference: "John 3:16" },
  { text: "I can do all this through him who gives me strength.", reference: "Philippians 4:13" },
  { text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.", reference: "Proverbs 3:5-6" },
  { text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.", reference: "Jeremiah 29:11" },
  { text: "The Lord is my shepherd, I lack nothing.", reference: "Psalm 23:1" },
  { text: "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.", reference: "Joshua 1:9" },
  { text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.", reference: "Romans 8:28" },
  { text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.", reference: "Philippians 4:6" },
  { text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.", reference: "Isaiah 40:31" },
  { text: "For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline.", reference: "2 Timothy 1:7" },
  { text: "Come to me, all you who are weary and burdened, and I will give you rest.", reference: "Matthew 11:28" },
  { text: "The Lord himself goes before you and will be with you; he will never leave you nor forsake you.", reference: "Deuteronomy 31:8" },
  { text: "Your word is a lamp for my feet, a light on my path.", reference: "Psalm 119:105" },
  { text: "Be still, and know that I am God.", reference: "Psalm 46:10" },
  { text: "Love the Lord your God with all your heart and with all your soul and with all your mind.", reference: "Matthew 22:37" },
  { text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit.", reference: "Psalm 34:18" },
  { text: "Cast all your anxiety on him because he cares for you.", reference: "1 Peter 5:7" },
  { text: "I am the way and the truth and the life. No one comes to the Father except through me.", reference: "John 14:6" },
  { text: "Even though I walk through the darkest valley, I will fear no evil, for you are with me.", reference: "Psalm 23:4" },
  { text: "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God.", reference: "Ephesians 2:8" },
  { text: "The Lord bless you and keep you; the Lord make his face shine on you and be gracious to you.", reference: "Numbers 6:24-25" },
  { text: "Create in me a pure heart, O God, and renew a steadfast spirit within me.", reference: "Psalm 51:10" },
  { text: "But seek first his kingdom and his righteousness, and all these things will be given to you as well.", reference: "Matthew 6:33" },
  { text: "If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.", reference: "James 1:5" },
  { text: "God is our refuge and strength, an ever-present help in trouble.", reference: "Psalm 46:1" },
  { text: "I have been crucified with Christ and I no longer live, but Christ lives in me.", reference: "Galatians 2:20" },
  { text: "Greater love has no one than this: to lay down one's life for one's friends.", reference: "John 15:13" },
  { text: "The steadfast love of the Lord never ceases; his mercies never come to an end; they are new every morning.", reference: "Lamentations 3:22-23" },
  { text: "Delight yourself in the Lord, and he will give you the desires of your heart.", reference: "Psalm 37:4" },
  { text: "No, in all these things we are more than conquerors through him who loved us.", reference: "Romans 8:37" },
  { text: "Let your light shine before others, that they may see your good deeds and glorify your Father in heaven.", reference: "Matthew 5:16" },
  { text: "For where two or three gather in my name, there am I with them.", reference: "Matthew 18:20" },
  { text: "I praise you because I am fearfully and wonderfully made; your works are wonderful, I know that full well.", reference: "Psalm 139:14" },
  { text: "Above all else, guard your heart, for everything you do flows from it.", reference: "Proverbs 4:23" },
  { text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind.", reference: "Romans 12:2" },
  { text: "The heart of man plans his way, but the Lord establishes his steps.", reference: "Proverbs 16:9" },
  { text: "He heals the brokenhearted and binds up their wounds.", reference: "Psalm 147:3" },
  { text: "Give thanks to the Lord, for he is good; his love endures forever.", reference: "Psalm 107:1" },
  { text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!", reference: "2 Corinthians 5:17" },
  { text: "For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God.", reference: "Romans 8:38-39" },
  { text: "The Lord is my light and my salvation — whom shall I fear?", reference: "Psalm 27:1" },
  { text: "Ask and it will be given to you; seek and you will find; knock and the door will be opened to you.", reference: "Matthew 7:7" },
  { text: "Now faith is confidence in what we hope for and assurance about what we do not see.", reference: "Hebrews 11:1" },
  { text: "Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up.", reference: "Galatians 6:9" },
  { text: "Rejoice always, pray continually, give thanks in all circumstances; for this is God's will for you in Christ Jesus.", reference: "1 Thessalonians 5:16-18" },
  { text: "The name of the Lord is a fortified tower; the righteous run to it and are safe.", reference: "Proverbs 18:10" },
  { text: "For God did not send his Son into the world to condemn the world, but to save the world through him.", reference: "John 3:17" },
  { text: "My grace is sufficient for you, for my power is made perfect in weakness.", reference: "2 Corinthians 12:9" },
  { text: "He gives strength to the weary and increases the power of the weak.", reference: "Isaiah 40:29" },
  { text: "Whoever walks in integrity walks securely, but whoever takes crooked paths will be found out.", reference: "Proverbs 10:9" },
  { text: "The grass withers and the flowers fall, but the word of our God endures forever.", reference: "Isaiah 40:8" },
  { text: "Jesus Christ is the same yesterday and today and forever.", reference: "Hebrews 13:8" },
  { text: "Set your minds on things above, not on earthly things.", reference: "Colossians 3:2" },
  { text: "And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.", reference: "Philippians 4:7" },
  { text: "You are the light of the world. A town built on a hill cannot be hidden.", reference: "Matthew 5:14" },
  { text: "For the word of God is alive and active. Sharper than any double-edged sword.", reference: "Hebrews 4:12" },
  { text: "With man this is impossible, but with God all things are possible.", reference: "Matthew 19:26" },
  { text: "I will never leave you nor forsake you.", reference: "Hebrews 13:5" },
  { text: "Taste and see that the Lord is good; blessed is the one who takes refuge in him.", reference: "Psalm 34:8" },
  { text: "The Lord your God is with you, the Mighty Warrior who saves. He will take great delight in you.", reference: "Zephaniah 3:17" },
  { text: "This is the day the Lord has made; let us rejoice and be glad in it.", reference: "Psalm 118:24" },
  // ── Extended set — brings total to 365 for full-year rotation ────────────
  { text: "The Lord is my rock, my fortress and my deliverer; my God is my rock, in whom I take refuge.", reference: "Psalm 18:2" },
  { text: "Commit to the Lord whatever you do, and he will establish your plans.", reference: "Proverbs 16:3" },
  { text: "Have I not commanded you? Be strong and courageous. Do not be afraid; do not be discouraged.", reference: "Joshua 1:9" },
  { text: "Search me, God, and know my heart; test me and know my anxious thoughts.", reference: "Psalm 139:23" },
  { text: "The Lord is good, a refuge in times of trouble. He cares for those who trust in him.", reference: "Nahum 1:7" },
  { text: "Humble yourselves, therefore, under God's mighty hand, that he may lift you up in due time.", reference: "1 Peter 5:6" },
  { text: "Let the word of Christ dwell in you richly as you teach and admonish one another with all wisdom.", reference: "Colossians 3:16" },
  { text: "I lift up my eyes to the mountains — where does my help come from? My help comes from the Lord, the Maker of heaven and earth.", reference: "Psalm 121:1-2" },
  { text: "Do not let your hearts be troubled. You believe in God; believe also in me.", reference: "John 14:1" },
  { text: "For we live by faith, not by sight.", reference: "2 Corinthians 5:7" },
  { text: "Draw near to God, and he will draw near to you.", reference: "James 4:8" },
  { text: "The Lord will fight for you; you need only to be still.", reference: "Exodus 14:14" },
  { text: "Blessed are the pure in heart, for they will see God.", reference: "Matthew 5:8" },
  { text: "A friend loves at all times, and a brother is born for a time of adversity.", reference: "Proverbs 17:17" },
  { text: "The Lord is my strength and my song; he has given me victory.", reference: "Exodus 15:2" },
  { text: "In him we have redemption through his blood, the forgiveness of sins, in accordance with the riches of God's grace.", reference: "Ephesians 1:7" },
  { text: "You will seek me and find me when you seek me with all your heart.", reference: "Jeremiah 29:13" },
  { text: "My flesh and my heart may fail, but God is the strength of my heart and my portion forever.", reference: "Psalm 73:26" },
  { text: "For it is God who works in you to will and to act in order to fulfill his good purpose.", reference: "Philippians 2:13" },
  { text: "He is before all things, and in him all things hold together.", reference: "Colossians 1:17" },
  { text: "God is not unjust; he will not forget your work and the love you have shown him.", reference: "Hebrews 6:10" },
  { text: "I sought the Lord, and he answered me; he delivered me from all my fears.", reference: "Psalm 34:4" },
  { text: "The name of the Lord is a fortified tower; the righteous run to it and are safe.", reference: "Proverbs 18:10" },
  { text: "There is no fear in love. But perfect love drives out fear.", reference: "1 John 4:18" },
  { text: "Blessed is the one who perseveres under trial because, having stood the test, that person will receive the crown of life.", reference: "James 1:12" },
  { text: "The Lord watches over you — the Lord is your shade at your right hand.", reference: "Psalm 121:5" },
  { text: "For we are God's handiwork, created in Christ Jesus to do good works.", reference: "Ephesians 2:10" },
  { text: "Whoever drinks the water I give them will never thirst. Indeed, the water I give them will become in them a spring of water welling up to eternal life.", reference: "John 4:14" },
  { text: "The Lord gives strength to his people; the Lord blesses his people with peace.", reference: "Psalm 29:11" },
  { text: "In their hearts humans plan their course, but the Lord establishes their steps.", reference: "Proverbs 16:9" },
  { text: "Not by might nor by power, but by my Spirit, says the Lord Almighty.", reference: "Zechariah 4:6" },
  { text: "Come near to God and he will come near to you.", reference: "James 4:8" },
  { text: "Every good and perfect gift is from above, coming down from the Father of the heavenly lights.", reference: "James 1:17" },
  { text: "The Lord is my helper; I will not be afraid. What can mere mortals do to me?", reference: "Hebrews 13:6" },
  { text: "Praise the Lord, my soul, and forget not all his benefits — who forgives all your sins and heals all your diseases.", reference: "Psalm 103:2-3" },
  { text: "But God demonstrates his own love for us in this: While we were still sinners, Christ died for us.", reference: "Romans 5:8" },
  { text: "How great is the love the Father has lavished on us, that we should be called children of God!", reference: "1 John 3:1" },
  { text: "For where your treasure is, there your heart will be also.", reference: "Matthew 6:21" },
  { text: "Whoever finds their life will lose it, and whoever loses their life for my sake will find it.", reference: "Matthew 10:39" },
  { text: "I am the resurrection and the life. The one who believes in me will live, even though they die.", reference: "John 11:25" },
  { text: "Let us hold unswervingly to the hope we profess, for he who promised is faithful.", reference: "Hebrews 10:23" },
  { text: "The Lord is close to all who call on him, to all who call on him in truth.", reference: "Psalm 145:18" },
  { text: "For the Son of Man came to seek and to save the lost.", reference: "Luke 19:10" },
  { text: "I have been crucified with Christ. It is no longer I who live, but Christ who lives in me.", reference: "Galatians 2:20" },
  { text: "Be completely humble and gentle; be patient, bearing with one another in love.", reference: "Ephesians 4:2" },
  { text: "The Lord reigns forever; he has established his throne for judgment.", reference: "Psalm 9:7" },
  { text: "Do not be overcome by evil, but overcome evil with good.", reference: "Romans 12:21" },
  { text: "He who began a good work in you will carry it on to completion until the day of Christ Jesus.", reference: "Philippians 1:6" },
  { text: "May the God of hope fill you with all joy and peace as you trust in him.", reference: "Romans 15:13" },
  { text: "Where can I go from your Spirit? Where can I flee from your presence?", reference: "Psalm 139:7" },
  { text: "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds.", reference: "James 1:2" },
  { text: "Love your enemies and pray for those who persecute you.", reference: "Matthew 5:44" },
  { text: "The Lord himself goes before you and will be with you; he will never leave you nor forsake you. Do not be afraid.", reference: "Deuteronomy 31:8" },
  { text: "He gives power to the faint, and to him who has no might he increases strength.", reference: "Isaiah 40:29" },
  { text: "Surely goodness and love will follow me all the days of my life, and I will dwell in the house of the Lord forever.", reference: "Psalm 23:6" },
  { text: "I am the bread of life. Whoever comes to me will never go hungry, and whoever believes in me will never be thirsty.", reference: "John 6:35" },
  { text: "So if the Son sets you free, you will be free indeed.", reference: "John 8:36" },
  { text: "Now may the Lord of peace himself give you peace at all times and in every way.", reference: "2 Thessalonians 3:16" },
  { text: "The Spirit of God, who raised Jesus from the dead, lives in you.", reference: "Romans 8:11" },
  { text: "Blessed are those who hunger and thirst for righteousness, for they will be filled.", reference: "Matthew 5:6" },
  { text: "I will instruct you and teach you in the way you should go; I will counsel you with my loving eye on you.", reference: "Psalm 32:8" },
  { text: "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness.", reference: "Galatians 5:22" },
  { text: "Do nothing out of selfish ambition or vain conceit. Rather, in humility value others above yourselves.", reference: "Philippians 2:3" },
  { text: "And my God will meet all your needs according to the riches of his glory in Christ Jesus.", reference: "Philippians 4:19" },
  { text: "For our struggle is not against flesh and blood, but against the spiritual forces of evil in the heavenly realms.", reference: "Ephesians 6:12" },
  { text: "Love must be sincere. Hate what is evil; cling to what is good.", reference: "Romans 12:9" },
  { text: "Give thanks to the Lord, for he is good; his love endures forever.", reference: "Psalm 136:1" },
  { text: "For this reason I kneel before the Father, from whom every family in heaven and on earth derives its name.", reference: "Ephesians 3:14-15" },
  { text: "When I am afraid, I put my trust in you.", reference: "Psalm 56:3" },
  { text: "The Lord is my light and my salvation — whom shall I fear? The Lord is the stronghold of my life — of whom shall I be afraid?", reference: "Psalm 27:1" },
  { text: "Peace I leave with you; my peace I give you. I do not give to you as the world gives. Do not let your hearts be troubled.", reference: "John 14:27" },
  { text: "Who shall separate us from the love of Christ? Shall trouble or hardship or persecution or famine or nakedness or danger or sword?", reference: "Romans 8:35" },
  { text: "For the Lord is good and his love endures forever; his faithfulness continues through all generations.", reference: "Psalm 100:5" },
  { text: "Finally, brothers and sisters, whatever is true, whatever is noble, whatever is right — think about such things.", reference: "Philippians 4:8" },
  { text: "Therefore, since we are surrounded by such a great cloud of witnesses, let us throw off everything that hinders.", reference: "Hebrews 12:1" },
  { text: "For the Lord takes delight in his people; he crowns the humble with victory.", reference: "Psalm 149:4" },
  { text: "Anyone who loves me will obey my teaching. My Father will love them, and we will come to them and make our home with them.", reference: "John 14:23" },
  { text: "The Lord is not slow in keeping his promise, as some understand slowness. Instead he is patient with you.", reference: "2 Peter 3:9" },
  { text: "See, I am doing a new thing! Now it springs up; do you not perceive it?", reference: "Isaiah 43:19" },
  { text: "But thanks be to God! He gives us the victory through our Lord Jesus Christ.", reference: "1 Corinthians 15:57" },
  { text: "Your statutes are my heritage forever; they are the joy of my heart.", reference: "Psalm 119:111" },
  { text: "To him who is able to do immeasurably more than all we ask or imagine, according to his power that is at work within us — to him be glory.", reference: "Ephesians 3:20-21" },
  { text: "What, then, shall we say in response to these things? If God is for us, who can be against us?", reference: "Romans 8:31" },
  { text: "Let your gentleness be evident to all. The Lord is near.", reference: "Philippians 4:5" },
  { text: "The Lord upholds all who fall and lifts up all who are bowed down.", reference: "Psalm 145:14" },
  { text: "Do not judge, and you will not be judged. Do not condemn, and you will not be condemned. Forgive, and you will be forgiven.", reference: "Luke 6:37" },
  { text: "The heart of the discerning acquires knowledge, for the ears of the wise seek it out.", reference: "Proverbs 18:15" },
  { text: "Blessed are the merciful, for they will be shown mercy.", reference: "Matthew 5:7" },
  { text: "You, Lord, are my lamp; the Lord turns my darkness into light.", reference: "2 Samuel 22:29" },
  { text: "The Lord your God is in your midst, a mighty one who will save; he will rejoice over you with gladness.", reference: "Zephaniah 3:17" },
  { text: "Praise be to the God and Father of our Lord Jesus Christ, the Father of compassion and the God of all comfort.", reference: "2 Corinthians 1:3" },
  { text: "We love because he first loved us.", reference: "1 John 4:19" },
  { text: "For the wages of sin is death, but the gift of God is eternal life in Christ Jesus our Lord.", reference: "Romans 6:23" },
  { text: "I praise you because I am fearfully and wonderfully made; your works are wonderful.", reference: "Psalm 139:14" },
  { text: "For where two or three gather in my name, there am I with them.", reference: "Matthew 18:20" },
  { text: "And the God of all grace, who called you to his eternal glory in Christ, after you have suffered a little while, will himself restore you.", reference: "1 Peter 5:10" },
  { text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.", reference: "Philippians 4:6" },
  { text: "He makes me lie down in green pastures, he leads me beside quiet waters, he refreshes my soul.", reference: "Psalm 23:2-3" },
  { text: "Come to me, all you who are weary and burdened, and I will give you rest. Take my yoke upon you and learn from me.", reference: "Matthew 11:28-29" },
  { text: "Yet this I call to mind and therefore I have hope: Because of the Lord's great love we are not consumed.", reference: "Lamentations 3:21-22" },
  { text: "Jesus looked at them and said, 'With man this is impossible, but not with God; all things are possible with God.'", reference: "Mark 10:27" },
  { text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles.", reference: "Isaiah 40:31" },
  { text: "I have told you these things, so that in me you may have peace. In this world you will have trouble. But take heart! I have overcome the world.", reference: "John 16:33" },
  { text: "He restores my soul. He leads me in paths of righteousness for his name's sake.", reference: "Psalm 23:3" },
  { text: "Devote yourselves to prayer, being watchful and thankful.", reference: "Colossians 4:2" },
  { text: "I will praise you, Lord, with all my heart; I will tell of all your wonderful deeds.", reference: "Psalm 9:1" },
  { text: "For in him we live and move and have our being.", reference: "Acts 17:28" },
  { text: "But seek first his kingdom and his righteousness, and all these things will be given to you as well.", reference: "Matthew 6:33" },
  { text: "May the Lord make your love increase and overflow for each other and for everyone else.", reference: "1 Thessalonians 3:12" },
  { text: "The Lord bless you and keep you; the Lord make his face shine on you and be gracious to you; the Lord turn his face toward you and give you peace.", reference: "Numbers 6:24-26" },
  { text: "In the beginning was the Word, and the Word was with God, and the Word was God.", reference: "John 1:1" },
  { text: "Do not be conformed to this world, but be transformed by the renewal of your mind.", reference: "Romans 12:2" },
  { text: "The Lord is my shepherd; I shall not want.", reference: "Psalm 23:1" },
  { text: "Blessed are the poor in spirit, for theirs is the kingdom of heaven.", reference: "Matthew 5:3" },
  { text: "You are my hiding place; you will protect me from trouble and surround me with songs of deliverance.", reference: "Psalm 32:7" },
  { text: "And whatever you do, whether in word or deed, do it all in the name of the Lord Jesus.", reference: "Colossians 3:17" },
  { text: "Whoever claims to love God yet hates a brother or sister is a liar.", reference: "1 John 4:20" },
  { text: "But you, Lord, are a compassionate and gracious God, slow to anger, abounding in love and faithfulness.", reference: "Psalm 86:15" },
  { text: "For the Lord is righteous, he loves justice; the upright will see his face.", reference: "Psalm 11:7" },
  { text: "I will never leave you nor forsake you.", reference: "Hebrews 13:5" },
  { text: "The Lord is compassionate and gracious, slow to anger, abounding in love.", reference: "Psalm 103:8" },
  { text: "Therefore confess your sins to each other and pray for each other so that you may be healed.", reference: "James 5:16" },
  { text: "No temptation has overtaken you except what is common to mankind. And God is faithful.", reference: "1 Corinthians 10:13" },
  { text: "Teach me your way, Lord, that I may rely on your faithfulness; give me an undivided heart.", reference: "Psalm 86:11" },
  { text: "I can do all this through him who gives me strength.", reference: "Philippians 4:13" },
  { text: "The Lord your God is with you wherever you go.", reference: "Joshua 1:9" },
  { text: "He is the same God who equips me with strength and makes my way perfect.", reference: "Psalm 18:32" },
  { text: "And let us run with perseverance the race marked out for us, fixing our eyes on Jesus.", reference: "Hebrews 12:1-2" },
  { text: "Shout for joy to the Lord, all the earth. Worship the Lord with gladness.", reference: "Psalm 100:1-2" },
  { text: "For God so loved the world that he gave his one and only Son.", reference: "John 3:16" },
  { text: "The thief comes only to steal and kill and destroy; I have come that they may have life, and have it to the full.", reference: "John 10:10" },
  { text: "I am the vine; you are the branches. If you remain in me and I in you, you will bear much fruit.", reference: "John 15:5" },
  { text: "For my thoughts are not your thoughts, neither are your ways my ways, declares the Lord.", reference: "Isaiah 55:8" },
  { text: "The Lord is good to all; he has compassion on all he has made.", reference: "Psalm 145:9" },
  { text: "Blessed are the peacemakers, for they will be called children of God.", reference: "Matthew 5:9" },
  { text: "Be joyful in hope, patient in affliction, faithful in prayer.", reference: "Romans 12:12" },
  { text: "Nothing in all creation is hidden from God's sight.", reference: "Hebrews 4:13" },
  { text: "He who dwells in the shelter of the Most High will rest in the shadow of the Almighty.", reference: "Psalm 91:1" },
  { text: "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you.", reference: "Isaiah 41:10" },
  { text: "Rejoice in the Lord always. I will say it again: Rejoice!", reference: "Philippians 4:4" },
  { text: "He will wipe every tear from their eyes. There will be no more death or mourning or crying or pain.", reference: "Revelation 21:4" },
  { text: "Know that the Lord is God. It is he who made us, and we are his; we are his people, the sheep of his pasture.", reference: "Psalm 100:3" },
  { text: "The earth is the Lord's, and everything in it, the world, and all who live in it.", reference: "Psalm 24:1" },
  { text: "For to me, to live is Christ and to die is gain.", reference: "Philippians 1:21" },
  { text: "Whoever sows generously will also reap generously.", reference: "2 Corinthians 9:6" },
  { text: "The name of the Lord is a strong tower; the righteous man runs into it and is safe.", reference: "Proverbs 18:10" },
  { text: "Since, then, you have been raised with Christ, set your hearts on things above.", reference: "Colossians 3:1" },
  { text: "You, Lord, are forgiving and good, abounding in love to all who call to you.", reference: "Psalm 86:5" },
  { text: "My God, my God, why have you forsaken me? Yet you are enthroned as the Holy One.", reference: "Psalm 22:1,3" },
  { text: "Fear the Lord your God, serve him only and take your oaths in his name.", reference: "Deuteronomy 6:13" },
  { text: "God is our refuge and strength, an ever-present help in trouble.", reference: "Psalm 46:1" },
  { text: "Create in me a pure heart, O God, and renew a steadfast spirit within me.", reference: "Psalm 51:10" },
  { text: "How lovely is your dwelling place, Lord Almighty! My soul yearns, even faints, for the courts of the Lord.", reference: "Psalm 84:1-2" },
  { text: "A cheerful heart is good medicine, but a crushed spirit dries up the bones.", reference: "Proverbs 17:22" },
  { text: "God is spirit, and his worshipers must worship in the Spirit and in truth.", reference: "John 4:24" },
  { text: "Do not let wisdom and understanding out of your sight; preserve sound judgment and discretion.", reference: "Proverbs 3:21" },
  { text: "Those who trust in the Lord are like Mount Zion, which cannot be shaken but endures forever.", reference: "Psalm 125:1" },
  { text: "For no word from God will ever fail.", reference: "Luke 1:37" },
  { text: "Whoever has the Son has life; whoever does not have the Son of God does not have life.", reference: "1 John 5:12" },
  { text: "The name of the Lord is a fortified tower; the righteous run to it and are safe.", reference: "Proverbs 18:10" },
  { text: "Wait for the Lord; be strong and take heart and wait for the Lord.", reference: "Psalm 27:14" },
  { text: "For I am the Lord your God who takes hold of your right hand and says to you, Do not fear; I will help you.", reference: "Isaiah 41:13" },
  { text: "This is how we know what love is: Jesus Christ laid down his life for us.", reference: "1 John 3:16" },
  { text: "He will cover you with his feathers, and under his wings you will find refuge; his faithfulness will be your shield and rampart.", reference: "Psalm 91:4" },
  { text: "You are a chosen people, a royal priesthood, a holy nation, God's special possession.", reference: "1 Peter 2:9" },
  { text: "His divine power has given us everything we need for a godly life.", reference: "2 Peter 1:3" },
  { text: "How priceless is your unfailing love, O God! People take refuge in the shadow of your wings.", reference: "Psalm 36:7" },
  { text: "Let the morning bring me word of your unfailing love, for I have put my trust in you.", reference: "Psalm 143:8" },
  { text: "Your word is a lamp for my feet, a light on my path.", reference: "Psalm 119:105" },
  { text: "See what great love the Father has lavished on us, that we should be called children of God!", reference: "1 John 3:1" },
  { text: "Yet to all who did receive him, to those who believed in his name, he gave the right to become children of God.", reference: "John 1:12" },
  { text: "You, Lord, keep my lamp burning; my God turns my darkness into light.", reference: "Psalm 18:28" },
  { text: "Do your best to present yourself to God as one approved, a worker who does not need to be ashamed.", reference: "2 Timothy 2:15" },
  { text: "Everyone who calls on the name of the Lord will be saved.", reference: "Romans 10:13" },
  { text: "Take delight in the Lord, and he will give you the desires of your heart.", reference: "Psalm 37:4" },
  { text: "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God.", reference: "Ephesians 2:8" },
  { text: "The Lord directs the steps of the godly. He delights in every detail of their lives.", reference: "Psalm 37:23" },
  { text: "Be still before the Lord and wait patiently for him.", reference: "Psalm 37:7" },
  { text: "How beautiful on the mountains are the feet of those who bring good news, who proclaim peace.", reference: "Isaiah 52:7" },
  { text: "Let everything that has breath praise the Lord.", reference: "Psalm 150:6" },
  { text: "Give ear to my words, O Lord; consider my sighing. Listen to my cry for help.", reference: "Psalm 5:1-2" },
  { text: "My help comes from the Lord, who made heaven and earth.", reference: "Psalm 121:2" },
  { text: "The eternal God is your refuge, and underneath are the everlasting arms.", reference: "Deuteronomy 33:27" },
  { text: "I keep my eyes always on the Lord. With him at my right hand, I will not be shaken.", reference: "Psalm 16:8" },
  { text: "The Lord has done it this very day; let us rejoice today and be glad.", reference: "Psalm 118:24" },
  { text: "Let us therefore approach God's throne of grace with confidence, so that we may receive mercy.", reference: "Hebrews 4:16" },
  { text: "He has shown you, O mortal, what is good. And what does the Lord require of you? To act justly and to love mercy and to walk humbly with your God.", reference: "Micah 6:8" },
  { text: "But the Lord said to Samuel, 'Do not consider his appearance or his height, for the Lord looks at the heart.'", reference: "1 Samuel 16:7" },
  { text: "You are my God, and I will praise you; you are my God, and I will exalt you.", reference: "Psalm 118:28" },
  { text: "Now to him who is able to do far more abundantly than all that we ask or think, according to the power at work within us.", reference: "Ephesians 3:20" },
  { text: "For the mountains may depart and the hills be removed, but my steadfast love shall not depart from you.", reference: "Isaiah 54:10" },
  { text: "The Lord is good to those whose hope is in him, to the one who seeks him.", reference: "Lamentations 3:25" },
  { text: "Light in a messenger's eyes brings joy to the heart, and good news gives health to the bones.", reference: "Proverbs 15:30" },
  { text: "I have hidden your word in my heart that I might not sin against you.", reference: "Psalm 119:11" },
  { text: "Whether you turn to the right or to the left, your ears will hear a voice behind you, saying, 'This is the way; walk in it.'", reference: "Isaiah 30:21" },
  { text: "Open my eyes that I may see wonderful things in your law.", reference: "Psalm 119:18" },
  { text: "The Lord is gracious and righteous; our God is full of compassion.", reference: "Psalm 116:5" },
  { text: "Enter his gates with thanksgiving and his courts with praise; give thanks to him and praise his name.", reference: "Psalm 100:4" },
  { text: "A new command I give you: Love one another. As I have loved you, so you must love one another.", reference: "John 13:34" },
  { text: "For I am the Lord your God, the Holy One of Israel, your Savior.", reference: "Isaiah 43:3" },
  { text: "You are my refuge and my shield; I have put my hope in your word.", reference: "Psalm 119:114" },
  { text: "The Lord will keep you from all harm — he will watch over your life.", reference: "Psalm 121:7" },
  { text: "Let the redeemed of the Lord tell their story — those he redeemed from the hand of the foe.", reference: "Psalm 107:2" },
  { text: "But I trust in your unfailing love; my heart rejoices in your salvation.", reference: "Psalm 13:5" },
  { text: "Cast your cares on the Lord and he will sustain you; he will never let the righteous be shaken.", reference: "Psalm 55:22" },
  { text: "He is the atoning sacrifice for our sins, and not only for ours but also for the sins of the whole world.", reference: "1 John 2:2" },
  { text: "This is the confidence we have in approaching God: that if we ask anything according to his will, he hears us.", reference: "1 John 5:14" },
  { text: "The Lord has established his throne in heaven, and his kingdom rules over all.", reference: "Psalm 103:19" },
  { text: "For all have sinned and fall short of the glory of God, and all are justified freely by his grace.", reference: "Romans 3:23-24" },
  { text: "Since God did not spare even his own Son but gave him up for us all, won't he also give us everything else?", reference: "Romans 8:32" },
  { text: "The Lord is righteous in all his ways and faithful in all he does.", reference: "Psalm 145:17" },
  { text: "Let love and faithfulness never leave you; bind them around your neck, write them on the tablet of your heart.", reference: "Proverbs 3:3" },
  { text: "I have been young and now I am old, yet I have not seen the righteous forsaken or his children begging for bread.", reference: "Psalm 37:25" },
  { text: "By wisdom a house is built, and through understanding it is established; through knowledge its rooms are filled with rare and beautiful treasures.", reference: "Proverbs 24:3-4" },
  { text: "The Lord is my strength and my defense; he has become my salvation.", reference: "Psalm 118:14" },
  { text: "Be on your guard; stand firm in the faith; be courageous; be strong. Do everything in love.", reference: "1 Corinthians 16:13-14" },
  { text: "So we say with confidence, 'The Lord is my helper; I will not be afraid.'", reference: "Hebrews 13:6" },
  { text: "As a father has compassion on his children, so the Lord has compassion on those who fear him.", reference: "Psalm 103:13" },
  { text: "The Lord is near to all who call on him, to all who call on him in truth.", reference: "Psalm 145:18" },
  { text: "Let your roots grow down into him, and let your lives be built on him.", reference: "Colossians 2:7" },
  { text: "Happy are those who find wisdom, and those who get understanding.", reference: "Proverbs 3:13" },
  { text: "The Lord your God is with you, the Mighty Warrior who saves.", reference: "Zephaniah 3:17" },
  { text: "Who is like the Lord our God, the One who sits enthroned on high, who stoops down to look on the heavens and the earth?", reference: "Psalm 113:5-6" },
  { text: "I will sing of the Lord's great love forever; with my mouth I will make your faithfulness known through all generations.", reference: "Psalm 89:1" },
  { text: "Return to the Lord your God, for he is gracious and compassionate, slow to anger and abounding in love.", reference: "Joel 2:13" },
  { text: "Therefore, there is now no condemnation for those who are in Christ Jesus.", reference: "Romans 8:1" },
  { text: "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning.", reference: "Lamentations 3:22-23" },
  { text: "I will praise God's name in song and glorify him with thanksgiving.", reference: "Psalm 69:30" },
  { text: "For the Lord is good and his love endures forever; his faithfulness continues through all generations.", reference: "Psalm 100:5" },
  { text: "He has made everything beautiful in its time. He has also set eternity in the human heart.", reference: "Ecclesiastes 3:11" },
  { text: "The Lord detests lying lips, but he delights in people who are trustworthy.", reference: "Proverbs 12:22" },
  { text: "So in everything, do to others what you would have them do to you.", reference: "Matthew 7:12" },
  { text: "Jesus replied: 'Love the Lord your God with all your heart and with all your soul and with all your mind.'", reference: "Matthew 22:37" },
  { text: "And I am sure of this, that he who began a good work in you will bring it to completion at the day of Jesus Christ.", reference: "Philippians 1:6" },
  { text: "Whoever speaks, let him speak as one who speaks oracles of God; whoever serves, let him serve in the strength that God supplies.", reference: "1 Peter 4:11" },
  { text: "The prayer of a righteous person is powerful and effective.", reference: "James 5:16" },
  { text: "For the Lord your God is he who goes with you to fight for you against your enemies, to give you the victory.", reference: "Deuteronomy 20:4" },
  { text: "And Jesus said to him, 'If you can! All things are possible for one who believes.'", reference: "Mark 9:23" },
  { text: "I am with you and will watch over you wherever you go, and I will bring you back to this land.", reference: "Genesis 28:15" },
  { text: "The joy of the Lord is your strength.", reference: "Nehemiah 8:10" },
  { text: "I sought the Lord, and he answered me and delivered me from all my fears.", reference: "Psalm 34:4" },
  { text: "Truly I tell you, if you have faith as small as a mustard seed, you can say to this mountain, 'Move from here to there,' and it will move.", reference: "Matthew 17:20" },
  { text: "For you are a people holy to the Lord your God. The Lord your God has chosen you out of all the peoples on the face of the earth to be his people.", reference: "Deuteronomy 7:6" },
  { text: "Fix your thoughts on what is true, and honorable, and right, and pure, and lovely, and admirable.", reference: "Philippians 4:8" },
  { text: "You will keep in perfect peace those whose minds are steadfast, because they trust in you.", reference: "Isaiah 26:3" },
  { text: "He who did not spare his own Son but gave him up for us all, how will he not also with him graciously give us all things?", reference: "Romans 8:32" },
  { text: "It is God who arms me with strength and keeps my way secure.", reference: "Psalm 18:32" },
  { text: "Let the peace of Christ rule in your hearts, since as members of one body you were called to peace. And be thankful.", reference: "Colossians 3:15" },
  { text: "He who finds a wife finds what is good and receives favor from the Lord.", reference: "Proverbs 18:22" },
  { text: "As iron sharpens iron, so one person sharpens another.", reference: "Proverbs 27:17" },
  { text: "The Lord your God is in your midst, a mighty one who will save; he will rejoice over you with gladness.", reference: "Zephaniah 3:17" },
  { text: "Out of his fullness we have all received grace in place of grace already given.", reference: "John 1:16" },
  { text: "The Spirit himself testifies with our spirit that we are God's children.", reference: "Romans 8:16" },
  { text: "For the kingdom of God is not a matter of eating and drinking but of righteousness and peace and joy in the Holy Spirit.", reference: "Romans 14:17" },
  { text: "And now these three remain: faith, hope and love. But the greatest of these is love.", reference: "1 Corinthians 13:13" },
  { text: "For to set the mind on the flesh is death, but to set the mind on the Spirit is life and peace.", reference: "Romans 8:6" },
  { text: "The Lord is my shepherd; I shall not want.", reference: "Psalm 23:1" },
  { text: "Where can I go from your Spirit? Where can I flee from your presence? If I go up to the heavens, you are there.", reference: "Psalm 139:7-8" },
  { text: "Praise the Lord, all you nations; extol him, all you peoples. For great is his love toward us.", reference: "Psalm 117:1-2" },
  { text: "So whether you eat or drink or whatever you do, do it all for the glory of God.", reference: "1 Corinthians 10:31" },
  { text: "For I know that my Redeemer lives, and at the last he will stand upon the earth.", reference: "Job 19:25" },
  { text: "My sheep listen to my voice; I know them, and they follow me.", reference: "John 10:27" },
  { text: "The Word became flesh and made his dwelling among us. We have seen his glory.", reference: "John 1:14" },
  { text: "Yet you, Lord, are our Father. We are the clay, you are the potter; we are all the work of your hand.", reference: "Isaiah 64:8" },
  { text: "I will meditate on your precepts and fix my eyes on your ways.", reference: "Psalm 119:15" },
  { text: "He tends his flock like a shepherd: He gathers the lambs in his arms and carries them close to his heart.", reference: "Isaiah 40:11" },
  { text: "You are my King and my God, who decrees victories for Jacob.", reference: "Psalm 44:4" },
  { text: "But I have calmed and quieted my soul, like a weaned child with its mother; like a weaned child is my soul within me.", reference: "Psalm 131:2" },
  { text: "On the last and greatest day of the festival, Jesus stood and said in a loud voice, 'Let anyone who is thirsty come to me and drink.'", reference: "John 7:37" },
  { text: "Whoever is generous to the poor lends to the Lord, and he will repay him for his deed.", reference: "Proverbs 19:17" },
  { text: "Let us then with confidence draw near to the throne of grace, that we may receive mercy and find grace to help in time of need.", reference: "Hebrews 4:16" },
  { text: "Because he loves me, says the Lord, I will rescue him; I will protect him, for he acknowledges my name.", reference: "Psalm 91:14" },
  { text: "The Lord is a warrior; the Lord is his name.", reference: "Exodus 15:3" },
  { text: "I have loved you with an everlasting love; I have drawn you with unfailing kindness.", reference: "Jeremiah 31:3" },
  { text: "Righteousness exalts a nation, but sin condemns any people.", reference: "Proverbs 14:34" },
  { text: "He has delivered us from the domain of darkness and transferred us to the kingdom of his beloved Son.", reference: "Colossians 1:13" },
  { text: "And we know that God causes all things to work together for good to those who love God.", reference: "Romans 8:28" },
  { text: "There is no wisdom, no insight, no plan that can succeed against the Lord.", reference: "Proverbs 21:30" },
  { text: "One thing I ask from the Lord, this only do I seek: that I may dwell in the house of the Lord all the days of my life.", reference: "Psalm 27:4" },
  { text: "Your love, Lord, reaches to the heavens, your faithfulness to the skies.", reference: "Psalm 36:5" },
  { text: "For God chose the foolish things of the world to shame the wise; God chose the weak things of the world to shame the strong.", reference: "1 Corinthians 1:27" },
  { text: "The Lord's unfailing love surrounds the one who trusts in him.", reference: "Psalm 32:10" },
  { text: "Just as you received Christ Jesus as Lord, continue to live your lives in him.", reference: "Colossians 2:6" },
  { text: "My soul glorifies the Lord and my spirit rejoices in God my Savior.", reference: "Luke 1:46-47" },
  { text: "God sets the lonely in families, he leads out the prisoners with singing.", reference: "Psalm 68:6" },
  { text: "And we all, who with unveiled faces contemplate the Lord's glory, are being transformed into his image with ever-increasing glory.", reference: "2 Corinthians 3:18" },
  { text: "No one has ever seen God; but if we love one another, God lives in us and his love is made complete in us.", reference: "1 John 4:12" },
  { text: "Blessed is the nation whose God is the Lord, the people he chose for his inheritance.", reference: "Psalm 33:12" },
  { text: "I will exalt you, my God the King; I will praise your name for ever and ever.", reference: "Psalm 145:1" },
  { text: "As the deer pants for streams of water, so my soul pants for you, my God.", reference: "Psalm 42:1" },
  { text: "You are my God; have mercy on me, Lord, for I call to you all day long.", reference: "Psalm 86:3" },
  { text: "Let me hear what God the Lord will speak, for he will speak peace to his people.", reference: "Psalm 85:8" },
  { text: "For our citizenship is in heaven, from which we also eagerly wait for the Savior.", reference: "Philippians 3:20" },
  { text: "The Lord is my strength and my shield; my heart trusts in him, and he helps me.", reference: "Psalm 28:7" },
  { text: "Teach us to number our days, that we may gain a heart of wisdom.", reference: "Psalm 90:12" },
  { text: "The Lord reigns, he is robed in majesty; the Lord is robed in majesty and armed with strength.", reference: "Psalm 93:1" },
  { text: "For the Lord is the great God, the great King above all gods.", reference: "Psalm 95:3" },
  { text: "Blessed are those whose strength is in you, whose hearts are set on pilgrimage.", reference: "Psalm 84:5" },
  { text: "He who goes out weeping, carrying seed to sow, will return with songs of joy, carrying sheaves with him.", reference: "Psalm 126:6" },
  { text: "Salvation belongs to the Lord; your blessing be on your people!", reference: "Psalm 3:8" },
  { text: "For God, who said, 'Let light shine out of darkness,' made his light shine in our hearts.", reference: "2 Corinthians 4:6" },
  { text: "I will praise you, Lord my God, with all my heart; I will glorify your name forever.", reference: "Psalm 86:12" },
  { text: "When you pass through the waters, I will be with you; and when you pass through the rivers, they will not sweep over you.", reference: "Isaiah 43:2" },
  { text: "Hear my prayer, Lord; let my cry for help come to you.", reference: "Psalm 102:1" },
  { text: "Lord, you alone are my portion and my cup; you make my lot secure.", reference: "Psalm 16:5" },
  { text: "The fear of the Lord is the beginning of wisdom; all who follow his precepts have good understanding.", reference: "Psalm 111:10" },
];

export const generateDailyCache = functions.pubsub.schedule("30 2 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Generating daily cache (quiz + word of day + focus verse)");

    const today = dateKey(new Date());
    const topicTags = [
      "Anxiety & Fear", "Identity", "Purpose & Calling",
      "Forgiveness", "Prayer", "Relationships",
      "Doubt & Faith", "The Holy Spirit", "Suffering", "Spiritual Growth",
    ];

    try {
      const quizMap = await generateQuizBatch(topicTags);
      const quizData: Record<string, unknown> = {};
      for (const [tag, questions] of quizMap.entries()) {
        quizData[tag] = questions;
      }

      await db.collection("dailycache").doc(today).set(
        { quizQuestions: quizData, generatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
    } catch (err) {
      functions.logger.error("Quiz batch generation failed", err);
    }

    // ── Word of Day ───────────────────────────────────────────────────────────
    try {
      // Use today's spark passage as the source
      const manifest = await db.collection("sparkcache").doc(today).get();
      if (manifest.exists) {
        const { passageId, reference } = manifest.data() as { passageId: string; reference: string };
        const sparkDoc = await db
          .collection("sparkcache").doc(today)
          .collection(passageId).doc("kjv").get();

        if (sparkDoc.exists) {
          const passageText = (sparkDoc.data() as { verseText: string }).verseText;
          const wordOfDay = await generateWordOfDay(passageText, reference, "kjv");
          await db.collection("dailycache").doc(today).set(
            { wordOfDay, generatedAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
          );
          functions.logger.info("Word of day generated", { word: wordOfDay.word });
        }
      }
    } catch (err) {
      functions.logger.error("Word of day generation failed", err);
    }

    // ── Focus Verse (Verse of the Day) ────────────────────────────────────────
    let focusVerse: { text: string; reference: string } | null = null;
    try {
      const now = new Date();
      const startOfYear = new Date(now.getFullYear(), 0, 0);
      const dayOfYear = Math.floor((now.getTime() - startOfYear.getTime()) / 86_400_000);
      focusVerse = _FOCUS_VERSES[dayOfYear % _FOCUS_VERSES.length];
      await db.collection("dailycache").doc(today).set(
        { focusVerse },
        { merge: true }
      );
      functions.logger.info("Focus verse set", { reference: focusVerse.reference });
    } catch (err) {
      functions.logger.error("Focus verse generation failed", err);
    }

    // ── Daily Devotional (Dig Deeper) ─────────────────────────────────────────
    if (focusVerse) {
      try {
        const ddClient = getClaudeClient();
        const ddResponse = await ddClient.messages.create({
          model: MODELS.haiku,
          max_tokens: 600,
          system: `You are a daily devotional writer for Dig Deeper, a Bible study app for Christians who want to go deeper in Scripture.
Write warm, thoughtful devotionals that help people encounter God in their study. Your tone is pastoral but accessible — not academic, not preachy.
Always respond with valid JSON only — no markdown fences, no extra text.`,
          messages: [{
            role: "user",
            content: `Write a brief daily devotional for this verse:

${focusVerse.reference}: "${focusVerse.text}"

Return ONLY this JSON:
{
  "reflection": "3-4 warm, encouraging sentences that unpack the verse's meaning and why it matters today.",
  "prayerPrompt": "A single sentence beginning with 'Lord,' that turns the verse into a personal prayer.",
  "reflectionQuestion": "One thoughtful question to carry into the day — starts with a verb (e.g. 'Where', 'How', 'What')."
}`,
          }],
        });

        const ddRaw = (ddResponse.content[0] as { type: "text"; text: string }).text.trim();
        const ddStart = ddRaw.indexOf("{");
        const ddEnd = ddRaw.lastIndexOf("}");
        const devotional = JSON.parse(ddRaw.substring(ddStart, ddEnd + 1)) as {
          reflection: string;
          prayerPrompt: string;
          reflectionQuestion: string;
        };

        await db.collection("dailycache").doc(today).set(
          { devotional, devotionalGeneratedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        functions.logger.info("Dig Deeper daily devotional generated", { reference: focusVerse.reference });
      } catch (err) {
        functions.logger.error("Dig Deeper devotional generation failed", err);
      }
    }
  });

/**
 * Generates a short daily devotional (reflection, prayer prompt, application question)
 * tied to today's Quest passage. Cached in sparkcache/{today}.devotional so the app
 * can read it without a per-user Claude call.
 */
export const generateDailyDevotional = functions.pubsub.schedule("10 2 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Generating daily devotional");

    const today = dateKey(new Date());

    const manifest = await db.collection("sparkcache").doc(today).get();
    if (!manifest.exists) {
      functions.logger.warn("No spark manifest yet — skipping devotional");
      return;
    }

    const { passageId, reference } = manifest.data() as { passageId: string; reference: string };

    const sparkDoc = await db
      .collection("sparkcache").doc(today)
      .collection(passageId).doc("kjv").get();

    if (!sparkDoc.exists) {
      functions.logger.warn("No KJV spark doc — skipping devotional");
      return;
    }

    const passageText = (sparkDoc.data() as { verseText: string }).verseText;

    const client = getClaudeClient();
    const response = await client.messages.create({
      model: MODELS.haiku,
      max_tokens: 500,
      system: `You are a daily devotional writer for StudyFire, a Christian Bible study app affiliated with Joshua's Crossing Church in Denison, TX.
Core beliefs: Scripture is God's infallible Word; salvation is through faith in Jesus alone; God is personal and loving; the Church is the bride of Christ.
Write warm, concise devotionals that help busy people encounter God in under 2 minutes.
Always respond with valid JSON only — no markdown fences, no extra text.`,
      messages: [{
        role: "user",
        content: `Write a brief daily devotional for this verse:

${reference}: "${passageText}"

Return ONLY this JSON:
{
  "reflection": "3-4 warm, encouraging sentences that unpack the verse's meaning and why it matters today.",
  "prayerPrompt": "A single sentence beginning with 'Lord,' that turns the verse into a personal prayer.",
  "applicationQuestion": "One practical, introspective question to carry into the day — starts with a verb (e.g. 'Where', 'How', 'What')."
}`,
      }],
    });

    const raw = (response.content[0] as { type: "text"; text: string }).text.trim();
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    const devotional = JSON.parse(raw.substring(start, end + 1)) as {
      reflection: string;
      prayerPrompt: string;
      applicationQuestion: string;
    };

    await db.collection("sparkcache").doc(today).set(
      { devotional, devotionalGeneratedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    functions.logger.info("Daily devotional generated", { reference });
  });

/**
 * Replenishes grace day tokens every Monday.
 */
export const weeklyGraceReplenish = functions.pubsub.schedule("0 0 * * 1").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Replenishing grace day tokens");
    await replenishGraceDays();
  });

// ── Scheduled: Notifications ─────────────────────────────────────────────────

export const sendEveningStreakReminders = functions.pubsub.schedule("0 20 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Sending streak reminders");
    await sendStreakReminders();
  });

export const sendMorningFocusCompanion = functions.pubsub.schedule("30 9 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Sending focus companion");
    await sendFocusCompanion();
  });

export const sendDailyGroupDigests = functions.pubsub.schedule("0 19 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Sending group digests");
    await sendGroupDigests();
  });

export const sendDigDeeperMorning = functions.pubsub.schedule("0 8 * * *").timeZone("America/Chicago").onRun(async () => {
    functions.logger.info("Sending Dig Deeper morning reminders");
    await sendDigDeeperMorningReminder();
  });

// ── HTTPS Callable: AI Study ──────────────────────────────────────────────────

export const getAiStudy = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const data = reqData as StudyContext & { passageId: string };

  // Check if cached in Firestore already
  const cacheRef = db
    .collection("studycache")
    .doc(uid)
    .collection("passages")
    .doc(data.passageId);

  const cached = await cacheRef.get();
  if (cached.exists) {
    const cacheData = cached.data()!;
    const cacheAge = Date.now() - (cacheData.cachedAt as admin.firestore.Timestamp).toMillis();
    // Cache for 7 days
    if (cacheAge < 7 * 24 * 60 * 60 * 1000) {
      return cacheData.study;
    }
  }

  // TODO: re-enable premium check after RevenueCat setup

  const study = await generateAiStudy(data);

  // Cache the result
  await cacheRef.set({
    study,
    cachedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return study;
});

// ── HTTPS Callable: Sermon Debrief ────────────────────────────────────────────

export const generateDebrief = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }
  const raw = reqData ?? {};
  functions.logger.info("generateDebrief raw:", JSON.stringify(raw).substring(0, 200));
  try {
    const data: DebriefContext = {
      noteContent: raw.noteContent ?? raw.data?.noteContent ?? "",
      sermonTitle: raw.sermonTitle ?? raw.data?.sermonTitle,
      speaker: raw.speaker ?? raw.data?.speaker,
      scriptureRefs: raw.scriptureRefs ?? raw.data?.scriptureRefs ?? [],
      studyLevel: raw.studyLevel ?? raw.data?.studyLevel ?? "growing",
    };
    const result = await generateSermonDebrief(data);
    functions.logger.info("generateDebrief success");
    return result;
  } catch (err) {
    functions.logger.error("generateDebrief error", err);
    throw err;
  }
});

// ── HTTPS Callable: Suggest Sermon Title ─────────────────────────────────────

export const suggestTitle = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const { noteContent } = reqData as { noteContent: string };
  return { title: await suggestSermonTitle(noteContent) };
});

/// ── HTTPS Callable: Create Devotional from Sermon Note ────────────────────────

export const generateNoteDevotionalFn = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  const _uid = context.auth.uid;
  const _userDoc = await db.collection("users").doc(_uid).get();
  if (_userDoc.data()?.isPro !== true) {
    throw new functions.https.HttpsError("permission-denied", "Dig Deeper Pro required");
  }
  const raw = reqData ?? {};
  const { noteTitle, noteContent, speaker, passage } = raw as {
    noteTitle: string;
    noteContent: string;
    speaker?: string;
    passage?: string;
  };
  if (!noteContent) throw new functions.https.HttpsError("invalid-argument", "noteContent is required");
  try {
    return await generateNoteDevotional(noteTitle ?? "", noteContent, speaker, passage);
  } catch (err) {
    functions.logger.error("generateNoteDevotionalFn error", err);
    throw err;
  }
});

// ── HTTPS Callable: Record Session End ───────────────────────────────────────

export const recordSessionEnd = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const { xpEarned } = reqData as {
    xpEarned: number;
    sessionType: string;
  };

  // Award XP
  await db.collection("users").doc(uid).update({
    "profile.xp": admin.firestore.FieldValue.increment(xpEarned),
  });

  // Update streak
  const streakResult = await recordStudyActivity(uid);

  // Check level up
  const userSnap = await db.collection("users").doc(uid).get();
  const profile = userSnap.data()?.profile as Record<string, unknown>;
  const newXp = (profile?.xp as number) ?? 0;
  const newLevel = levelForXp(newXp);
  const oldLevel = (profile?.level as number) ?? 1;

  if (newLevel > oldLevel) {
    await db.collection("users").doc(uid).update({ "profile.level": newLevel });
  }

  // Check XP milestone badges
  const prevXp = newXp - xpEarned;
  const newBadges = checkXpBadges(prevXp, newXp);
  for (const badge of newBadges) {
    await db.collection("badges").doc(uid).collection("earned").doc(badge).set({
      earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      shared: false,
      shareCount: 0,
    });
  }

  return {
    newStreak: streakResult.newStreak,
    leveledUp: newLevel > oldLevel,
    newLevel: newLevel > oldLevel ? newLevel : null,
    newBadges,
    streakBroken: streakResult.streakBroken,
    milestoneReached: streakResult.milestoneReached,
  };
});

// ── HTTPS Callable: Update Memory Verse (SM-2) ────────────────────────────────

export const updateMemoryVerse = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const { verseId, percentCorrect } = reqData as {
    verseId: string;
    percentCorrect: number;
  };

  const verseRef = db
    .collection("memoryVerses")
    .doc(uid)
    .collection("verses")
    .doc(verseId);

  const snap = await verseRef.get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Verse not found");

  const data = snap.data()!;
  const card = {
    easeFactor: (data.easeFactor as number) ?? 250,
    interval: (data.interval as number) ?? 1,
    repetitions: (data.repetitions as number) ?? 0,
  };

  const grade = scoreToGrade(percentCorrect);
  const result = sm2Update(card, grade);

  await verseRef.update({
    easeFactor: result.easeFactor,
    interval: result.interval,
    repetitions: result.repetitions,
    lastReviewed: admin.firestore.FieldValue.serverTimestamp(),
    nextReviewDate: admin.firestore.Timestamp.fromDate(result.nextReviewDate),
    mastered: result.passed ? true : data.mastered,
  });

  return {
    passed: result.passed,
    nextReviewDays: result.interval,
    nextReviewDate: result.nextReviewDate.toISOString(),
  };
});

// ── HTTPS Callable: Register FCM Token ───────────────────────────────────────

export const registerFcmToken = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const { token } = reqData as { token: string };

  await db.collection("users").doc(uid).collection("fcmTokens").doc(token).set({
    token,
    registeredAt: admin.firestore.FieldValue.serverTimestamp(),
    platform: "ios",
  });

  return { success: true };
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function dateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}


const XP_LEVELS = [
  { level: 1, xp: 0 },
  { level: 2, xp: 500 },
  { level: 3, xp: 1500 },
  { level: 4, xp: 3500 },
  { level: 5, xp: 7000 },
  { level: 6, xp: 12000 },
  { level: 7, xp: 20000 },
];

function levelForXp(xp: number): number {
  let level = 1;
  for (const l of XP_LEVELS) {
    if (xp >= l.xp) level = l.level;
  }
  return level;
}

const XP_BADGE_MILESTONES: Record<number, string> = {
  100: "spark",
  500: "on_fire",
  1500: "burning_bright",
  3500: "unquenchable",
  7000: "flame_keeper",
  12000: "eternal_flame",
};

function checkXpBadges(oldXp: number, newXp: number): string[] {
  return Object.entries(XP_BADGE_MILESTONES)
    .filter(([threshold]) => oldXp < Number(threshold) && newXp >= Number(threshold))
    .map(([, badge]) => badge);
}

// ── Firestore Trigger: Award XP Milestone Badges ─────────────────────────────

/**
 * Fires on every users/{uid} write. When profile.xp increases past a milestone
 * threshold, writes the badge to badges/{uid}/earned/{badgeId}. Server-side so
 * clients cannot self-award badges by writing directly to Firestore.
 */
export const onXpUpdated = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const oldXp = (change.before.data()?.profile?.xp as number) ?? 0;
    const newXp = (change.after.data()?.profile?.xp as number) ?? 0;

    if (newXp <= oldXp) return; // XP didn't increase — nothing to check

    const uid = context.params.uid;
    const newBadges = checkXpBadges(oldXp, newXp);
    if (newBadges.length === 0) return;

    await Promise.all(
      newBadges.map((badge) =>
        db
          .collection("badges")
          .doc(uid)
          .collection("earned")
          .doc(badge)
          .set(
            {
              earnedAt: admin.firestore.FieldValue.serverTimestamp(),
              shared: false,
              shareCount: 0,
            },
            { merge: true } // idempotent — safe if trigger fires more than once
          )
      )
    );
  });

// ── Firestore Triggers: Prayer Request Notifications ─────────────────────────

/**
 * When a new prayer request is created, notify all group members.
 */
export const onPrayerRequestCreated = functions.firestore
  .document("groups/{groupId}/prayers/{prayerId}")
  .onCreate(async (snap, context) => {
    const { groupId } = context.params;
    const prayer = snap.data();
    const authorName: string = prayer.authorName ?? "Someone";
    const text: string = prayer.text ?? "";
    const preview = text.length > 80 ? text.substring(0, 80) + "…" : text;

    // Get group name and members
    const [groupSnap, membersSnap] = await Promise.all([
      db.collection("groups").doc(groupId).get(),
      db.collection("groups").doc(groupId).collection("members").get(),
    ]);
    const groupName: string = (groupSnap.data()?.displayName ?? groupSnap.data()?.name ?? "Your Group") as string;

    const sends: Promise<void>[] = [];
    for (const memberDoc of membersSnap.docs) {
      const uid = memberDoc.id;
      if (uid === prayer.authorUid) continue; // don't notify the poster
      if (memberDoc.data()?.mutedNotifications === true) continue;
      sends.push(
        sendPushNotification({
          uid,
          title: `🙏 ${authorName} in ${groupName}`,
          body: preview,
          data: { type: "prayer_request", groupId, prayerId: snap.id },
        })
      );
    }
    await Promise.allSettled(sends);
  });

/**
 * When a prayer is marked answered, notify all group members so they can
 * celebrate together. The author already knows (they tapped the button), so
 * they are excluded from the notification batch.
 */
export const onPrayerAnswered = functions.firestore
  .document("groups/{groupId}/prayers/{prayerId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    // Only fire when answered flips true
    if (before.answered || !after.answered) return;

    const { groupId } = context.params;
    const authorUid: string = after.authorUid;
    const authorName: string = after.authorName ?? "Someone";

    const [groupSnap, membersSnap] = await Promise.all([
      db.collection("groups").doc(groupId).get(),
      db.collection("groups").doc(groupId).collection("members").get(),
    ]);
    const groupName: string = (groupSnap.data()?.displayName ?? groupSnap.data()?.name ?? "Your Group") as string;

    const sends: Promise<void>[] = [];
    for (const memberDoc of membersSnap.docs) {
      const uid = memberDoc.id;
      if (uid === authorUid) continue; // author already knows — they tapped the button
      if (memberDoc.data()?.mutedNotifications === true) continue;
      sends.push(
        sendPushNotification({
          uid,
          title: `✅ Prayer Answered in ${groupName}!`,
          body: `${authorName}'s prayer request was answered. Praise God! 🙌`,
          data: { type: "prayer_answered", groupId, prayerId: change.after.id },
        })
      );
    }
    await Promise.allSettled(sends);
  });

// ── Firestore Triggers: Auto-Post to Group Feed ──────────────────────────────

/**
 * When a badge is earned (written by recordSessionEnd), auto-post to all groups
 * the user belongs to if their autoPostSettings allows badge sharing.
 */
export const onBadgeEarned = functions.firestore
  .document("badges/{uid}/earned/{badgeId}")
  .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const badgeId = context.params.badgeId;

    const groupsSnap = await db
      .collection("groups")
      .where("memberIds", "array-contains", uid)
      .get();

    if (groupsSnap.empty) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const name = (userSnap.data()?.profile?.name as string) ?? "Someone";

    const BADGE_LABELS: Record<string, string> = {
      spark: "earned the Spark badge 🔥",
      on_fire: "earned the On Fire badge 🔥🔥",
      burning_bright: "is Burning Bright 🔥🔥🔥",
      unquenchable: "is Unquenchable 🔥🔥🔥🔥",
      flame_keeper: "is a Flame Keeper 🏆",
      eternal_flame: "is the Eternal Flame 🏆✨",
    };

    const label = BADGE_LABELS[badgeId] ?? `earned the ${badgeId} badge`;

    const writes: Promise<unknown>[] = [];
    for (const groupDoc of groupsSnap.docs) {
      const autoPost = groupDoc.data()?.autoPostSettings?.badgeEarned !== false;
      if (!autoPost) continue;

      writes.push(
        groupDoc.ref.collection("feed").add({
          type: "badgeEarned",
          authorId: uid,
          authorName: name,
          content: `${name} ${label}`,
          badgeId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          comments: [],
          reactions: [],
        })
      );
    }
    await Promise.all(writes);
  });

/**
 * When a memory verse is added, award first_verse / ten_verses badges.
 */
export const onMemoryVerseAdded = functions.firestore
  .document("memoryVerses/{uid}/verses/{verseId}")
  .onCreate(async (_snap, context) => {
    const uid = context.params.uid;

    const versesSnap = await db
      .collection("memoryVerses")
      .doc(uid)
      .collection("verses")
      .get();
    const count = versesSnap.size;

    const badgeId = count === 1 ? "first_verse" : count === 10 ? "ten_verses" : null;
    if (!badgeId) return;

    const badgeRef = db.collection("badges").doc(uid).collection("earned").doc(badgeId);
    const existing = await badgeRef.get();
    if (existing.exists) return; // already earned

    const userSnap = await db.collection("users").doc(uid).get();
    const xp = (userSnap.data()?.profile?.xp as number) ?? 0;

    await badgeRef.set({
      earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      name: badgeId === "first_verse" ? "First Verse" : "Ten Verses",
      xpAtEarning: xp,
    });
  });

/**
 * When a memory verse is mastered (mastered field flips to true),
 * auto-post to groups.
 */
export const onMemoryVerseMastered = functions.firestore
  .document("memoryVerses/{uid}/verses/{verseId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before?.mastered || !after?.mastered) return; // only on first mastery

    const uid = context.params.uid;

    const groupsSnap = await db
      .collection("groups")
      .where("memberIds", "array-contains", uid)
      .get();

    if (groupsSnap.empty) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const name = (userSnap.data()?.profile?.name as string) ?? "Someone";
    const reference = (after.reference as string) ?? "a verse";

    const writes: Promise<unknown>[] = [];
    for (const groupDoc of groupsSnap.docs) {
      const autoPost = groupDoc.data()?.autoPostSettings?.memoryVerseMastered !== false;
      if (!autoPost) continue;

      writes.push(
        groupDoc.ref.collection("feed").add({
          type: "memoryVerseMastered",
          authorId: uid,
          authorName: name,
          content: `${name} just memorized ${reference}! 🧠✨`,
          verseReference: reference,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          comments: [],
          reactions: [],
        })
      );
    }
    await Promise.all(writes);
  });

/**
 * When a streak milestone is reached (recorded in streakMilestones sub-collection
 * by streak_manager.ts), auto-post to groups.
 */
export const onStreakMilestone = functions.firestore
  .document("users/{uid}/streakMilestones/{milestoneId}")
  .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const { days } = snap.data() as { days: number };

    const groupsSnap = await db
      .collection("groups")
      .where("memberIds", "array-contains", uid)
      .get();

    if (groupsSnap.empty) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const name = (userSnap.data()?.profile?.name as string) ?? "Someone";

    const writes: Promise<unknown>[] = [];
    for (const groupDoc of groupsSnap.docs) {
      const autoPost = groupDoc.data()?.autoPostSettings?.streakMilestone !== false;
      if (!autoPost) continue;

      writes.push(
        groupDoc.ref.collection("feed").add({
          type: "streakMilestone",
          authorId: uid,
          authorName: name,
          content: `${name} hit a ${days}-day streak! 🔥`,
          streakDays: days,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          comments: [],
          reactions: [],
        })
      );
    }
    await Promise.all(writes);
  });

// ── Helpers ───────────────────────────────────────────────────────────────────

// Curated passage rotation — cycles by day-of-year so each day gets fresh content.
// Add more passages to extend the rotation (aim for 52+ for a full year).
const PASSAGE_ROTATION: Array<{ id: string; text: string; reference: string }> = [
  { id: "jhn_3_16",  reference: "John 3:16",          text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life." },
  { id: "rom_8_28",  reference: "Romans 8:28",         text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose." },
  { id: "php_4_13",  reference: "Philippians 4:13",    text: "I can do all this through him who gives me strength." },
  { id: "jer_29_11", reference: "Jeremiah 29:11",      text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future." },
  { id: "psa_23_1",  reference: "Psalm 23:1",          text: "The Lord is my shepherd, I lack nothing." },
  { id: "pro_3_5",   reference: "Proverbs 3:5",        text: "Trust in the Lord with all your heart and lean not on your own understanding." },
  { id: "isa_40_31", reference: "Isaiah 40:31",        text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint." },
  { id: "mat_6_33",  reference: "Matthew 6:33",        text: "But seek first his kingdom and his righteousness, and all these things will be given to you as well." },
  { id: "rom_8_38",  reference: "Romans 8:38-39",      text: "For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God that is in Christ Jesus our Lord." },
  { id: "php_4_6",   reference: "Philippians 4:6-7",   text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus." },
  { id: "gal_2_20",  reference: "Galatians 2:20",      text: "I have been crucified with Christ and I no longer live, but Christ lives in me. The life I now live in the body, I live by faith in the Son of God, who loved me and gave himself for me." },
  { id: "psa_46_10", reference: "Psalm 46:10",         text: "He says, 'Be still, and know that I am God; I will be exalted among the nations, I will be exalted in the earth.'" },
  { id: "mat_11_28", reference: "Matthew 11:28-30",    text: "Come to me, all you who are weary and burdened, and I will give you rest. Take my yoke upon you and learn from me, for I am gentle and humble in heart, and you will find rest for your souls. For my yoke is easy and my burden is light." },
  { id: "jhn_14_6",  reference: "John 14:6",           text: "Jesus answered, 'I am the way and the truth and the life. No one comes to the Father except through me.'" },
  { id: "rom_12_2",  reference: "Romans 12:2",         text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind. Then you will be able to test and approve what God's will is—his good, pleasing and perfect will." },
  { id: "eph_2_8",   reference: "Ephesians 2:8-9",     text: "For it is by grace you have been saved, through faith—and this is not from yourselves, it is the gift of God—not by works, so that no one can boast." },
  { id: "psa_139_14",reference: "Psalm 139:14",        text: "I praise you because I am fearfully and wonderfully made; your works are wonderful, I know that full well." },
  { id: "isa_41_10", reference: "Isaiah 41:10",        text: "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand." },
  { id: "jhn_1_1",   reference: "John 1:1",            text: "In the beginning was the Word, and the Word was with God, and the Word was God." },
  { id: "1co_13_4",  reference: "1 Corinthians 13:4-7",text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs. Love does not delight in evil but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres." },
  { id: "psa_119_105",reference: "Psalm 119:105",      text: "Your word is a lamp for my feet, a light on my path." },
  { id: "mat_28_19", reference: "Matthew 28:19-20",    text: "Therefore go and make disciples of all nations, baptizing them in the name of the Father and of the Son and of the Holy Spirit, and teaching them to obey everything I have commanded you. And surely I am with you always, to the very end of the age." },
  { id: "rom_5_8",   reference: "Romans 5:8",          text: "But God demonstrates his own love for us in this: While we were still sinners, Christ died for us." },
  { id: "2co_5_17",  reference: "2 Corinthians 5:17",  text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!" },
  { id: "eph_6_10",  reference: "Ephesians 6:10-11",   text: "Finally, be strong in the Lord and in his mighty power. Put on the full armor of God, so that you can take your stand against the devil's schemes." },
  { id: "heb_11_1",  reference: "Hebrews 11:1",        text: "Now faith is confidence in what we hope for and assurance about what we do not see." },
  { id: "jas_1_2",   reference: "James 1:2-4",         text: "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds, because you know that the testing of your faith produces perseverance. Let perseverance finish its work so that you may be mature and complete, not lacking anything." },
  { id: "1pe_5_7",   reference: "1 Peter 5:7",         text: "Cast all your anxiety on him because he cares for you." },
  { id: "1jn_4_19",  reference: "1 John 4:19",         text: "We love because he first loved us." },
  { id: "psa_27_1",  reference: "Psalm 27:1",          text: "The Lord is my light and my salvation—whom shall I fear? The Lord is the stronghold of my life—of whom shall I be afraid?" },
  { id: "luk_1_37",  reference: "Luke 1:37",           text: "For no word from God will ever fail." },
  { id: "rom_8_1",   reference: "Romans 8:1",          text: "Therefore, there is now no condemnation for those who are in Christ Jesus." },
  { id: "psa_34_18", reference: "Psalm 34:18",         text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit." },
  { id: "isa_53_5",  reference: "Isaiah 53:5",         text: "But he was pierced for our transgressions, he was crushed for our iniquities; the punishment that brought us peace was on him, and by his wounds we are healed." },
  { id: "col_3_23",  reference: "Colossians 3:23-24",  text: "Whatever you do, work at it with all your heart, as working for the Lord, not for human masters, since you know that you will receive an inheritance from the Lord as a reward. It is the Lord Christ you are serving." },
  { id: "jhn_10_10", reference: "John 10:10",          text: "The thief comes only to steal and kill and destroy; I have come that they may have life, and have it to the full." },
  { id: "mat_5_14",  reference: "Matthew 5:14-16",     text: "You are the light of the world. A town built on a hill cannot be hidden. Neither do people light a lamp and put it under a bowl. Instead they put it on its stand, and it gives light to everyone in the house. In the same way, let your light shine before others, that they may see your good deeds and glorify your Father in heaven." },
  { id: "php_1_6",   reference: "Philippians 1:6",     text: "Being confident of this, that he who began a good work in you will carry it on to completion until the day of Christ Jesus." },
  { id: "2ti_1_7",   reference: "2 Timothy 1:7",       text: "For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline." },
  { id: "psa_37_4",  reference: "Psalm 37:4",          text: "Take delight in the Lord, and he will give you the desires of your heart." },
  { id: "rom_15_13", reference: "Romans 15:13",        text: "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit." },
  { id: "heb_12_1",  reference: "Hebrews 12:1-2",      text: "Therefore, since we are surrounded by such a great cloud of witnesses, let us throw off everything that hinders and the sin that so easily entangles. And let us run with perseverance the race marked out for us, fixing our eyes on Jesus, the pioneer and perfecter of faith." },
  { id: "lam_3_22",  reference: "Lamentations 3:22-23",text: "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness." },
  { id: "gal_5_22",  reference: "Galatians 5:22-23",   text: "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control. Against such things there is no law." },
  { id: "jhn_15_5",  reference: "John 15:5",           text: "I am the vine; you are the branches. If you remain in me and I in you, you will bear much fruit; apart from me you can do nothing." },
  { id: "mat_6_9",   reference: "Matthew 6:9-13",      text: "Our Father in heaven, hallowed be your name, your kingdom come, your will be done, on earth as it is in heaven. Give us today our daily bread. And forgive us our debts, as we also have forgiven our debtors. And lead us not into temptation, but deliver us from the evil one." },
  { id: "psa_91_1",  reference: "Psalm 91:1-2",        text: "Whoever dwells in the shelter of the Most High will rest in the shadow of the Almighty. I will say of the Lord, 'He is my refuge and my fortress, my God, in whom I trust.'" },
  { id: "eph_3_20",  reference: "Ephesians 3:20-21",   text: "Now to him who is able to do immeasurably more than all we ask or imagine, according to his power that is at work within us, to him be glory in the church and in Christ Jesus throughout all generations, for ever and ever! Amen." },
  { id: "act_1_8",   reference: "Acts 1:8",            text: "But you will receive power when the Holy Spirit comes on you; and you will be my witnesses in Jerusalem, and in all Judea and Samaria, and to the ends of the earth." },
  { id: "rev_3_20",  reference: "Revelation 3:20",     text: "Here I am! I stand at the door and knock. If anyone hears my voice and opens the door, I will come in and eat with that person, and they with me." },
  { id: "mic_6_8",   reference: "Micah 6:8",           text: "He has shown you, O mortal, what is good. And what does the Lord require of you? To act justly and to love mercy and to walk humbly with your God." },
  { id: "1co_10_13", reference: "1 Corinthians 10:13", text: "No temptation has overtaken you except what is common to mankind. And God is faithful; he will not let you be tempted beyond what you can bear. But when you are tempted, he will also provide a way out so that you can endure it." },
  { id: "deu_31_6",  reference: "Deuteronomy 31:6",    text: "Be strong and courageous. Do not be afraid or terrified because of them, for the Lord your God goes with you; he will never leave you nor forsake you." },
  { id: "2ch_7_14",  reference: "2 Chronicles 7:14",   text: "If my people, who are called by my name, will humble themselves and pray and seek my face and turn from their wicked ways, then I will hear from heaven, and I will forgive their sin and will heal their land." },
  { id: "psa_1_1",   reference: "Psalm 1:1-3",         text: "Blessed is the one who does not walk in step with the wicked or stand in the way that sinners take or sit in the company of mockers, but whose delight is in the law of the Lord, and who meditates on his law day and night. That person is like a tree planted by streams of water, which yields its fruit in season and whose leaf does not wither—whatever they do prospers." },
  { id: "jhn_8_32",  reference: "John 8:32",           text: "Then you will know the truth, and the truth will set you free." },
  { id: "rom_1_16",  reference: "Romans 1:16",         text: "For I am not ashamed of the gospel, because it is the power of God that brings salvation to everyone who believes: first to the Jew, then to the Gentile." },
];

function getTodaysPassages(date: Date = new Date()): Array<{ id: string; text: string; reference: string }> {
  // Pick passage by day-of-year so each day rotates automatically
  const start = new Date(date.getFullYear(), 0, 0);
  const diff = date.getTime() - start.getTime();
  const dayOfYear = Math.floor(diff / (1000 * 60 * 60 * 24));
  const index = dayOfYear % PASSAGE_ROTATION.length;
  return [PASSAGE_ROTATION[index]];
}

// ── HTTPS Callable: Word Study ────────────────────────────────────────────────
export const getWordStudy = functions.https.onCall(async (reqData, _context) => {
  const raw = reqData ?? {};
  const { word, verseRef, verseText } = raw;

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 600,
    system: "You are a Bible word study assistant. Always respond with valid JSON only, no other text.",
    messages: [{
      role: "user",
      content: `Do a word study on the word "${word}" from ${verseRef}: "${verseText}".

Return ONLY this JSON:
{
  "word": "${word}",
  "originalWord": "Hebrew or Greek word",
  "language": "Hebrew or Greek",
  "strongsNumber": "H1234 or G1234",
  "pronunciation": "phonetic pronunciation",
  "definition": "2-3 sentence definition focusing on biblical meaning",
  "usageInContext": "How this specific word is used in this verse and what it means here",
  "otherVerses": ["Reference 1", "Reference 2"],
  "applicationToday": "One practical sentence for modern application"
}`
    }]
  });

  const text = (response.content[0] as any).text;
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  return JSON.parse(text.substring(start, end + 1));
});

// ── HTTPS Callable: Ask Verse Question ───────────────────────────────────────

/** Per-feature daily limits for free users. */
const FREE_AI_LIMITS: Record<string, number> = {
  askVerseQuestion: 2,
  interpretVerse:   2,
  deepStudyVerse:   1,
  getVerseWordStudy: 2,
};

/**
 * Returns YYYY-MM-DD in UTC — used as the Firestore doc key for daily usage.
 */
function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Atomically increments the per-feature daily AI usage counter.
 * Returns { allowed: true, remaining } or { allowed: false, remaining: 0 }.
 * isPremium is read from Firestore — never trusted from the client.
 */
async function checkAndIncrementAiUsage(
  uid: string,
  feature: string
): Promise<{ allowed: boolean; remaining: number; limit: number }> {
  // Server-side isPremium check — ignore any value the client sends
  const userSnap = await db.collection("users").doc(uid).get();
  const isPremium = userSnap.data()?.profile?.isPremium === true;
  const limit = FREE_AI_LIMITS[feature] ?? 2;
  if (isPremium) return { allowed: true, remaining: 999, limit };

  const ref = db
    .collection("users")
    .doc(uid)
    .collection("aiUsage")
    .doc(`${feature}_${todayKey()}`);

  // Atomic increment + read in a transaction
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current: number = snap.exists ? (snap.data()?.count ?? 0) : 0;

    if (current >= limit) {
      return { allowed: false, remaining: 0, limit };
    }

    tx.set(ref, { count: current + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { allowed: true, remaining: limit - (current + 1), limit };
  });
}

export const askVerseQuestion = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText, question } = raw;

  if (!verseRef || !question) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or question");
  }

  // Require auth
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  // Rate-limit free users (isPremium verified server-side inside this function)
  const usage = await checkAndIncrementAiUsage(uid, "askVerseQuestion");
  if (!usage.allowed) {
    // Return a structured error the client can handle gracefully
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  // Reject suspiciously long or empty questions
  if (!question || typeof question !== "string" || question.trim().length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "Question is required");
  }
  if (question.length > 500) {
    throw new functions.https.HttpsError("invalid-argument", "Question is too long");
  }

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 400,
    system: "You are a Bible study assistant in a Christian app for ages 16-30. You ONLY answer questions about Scripture, theology, faith, prayer, and Christian living. If a user asks anything unrelated to the Bible or Christian faith — including inappropriate, offensive, or explicit topics — respond only with: 'I can only help with Bible study questions.' Never generate harmful, sexual, violent, or off-topic content under any circumstances. Keep answers clear and encouraging, 2-4 sentences.",
    messages: [{
      role: "user",
      content: `Verse: ${verseRef} - "${verseText}"\n\nQuestion: ${question}`
    }]
  });

  const answer = (response.content[0] as any).text;
  return { answer, remaining: usage.remaining };
});

/**
 * Premium: Greek / Hebrew word study for a verse.
 * Identifies 3-5 key original-language terms, returns transliteration,
 * Strong's number, literal meaning, and a plain-English insight.
 */
export const getVerseWordStudy = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText } = raw;

  if (!verseRef || !verseText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or verseText");
  }

  // Require auth
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  // Word study counts against the daily limit (isPremium verified server-side)
  const usage = await checkAndIncrementAiUsage(uid, "getVerseWordStudy");
  if (!usage.allowed) {
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  // Determine testament from book abbreviation or reference
  // NT books start with: matt, mar, luke, joh, act, rom, 1co, 2co, gal, eph,
  // php, col, 1th, 2th, 1ti, 2ti, tit, phm, heb, jas, 1pe, 2pe, 1jo, 2jo,
  // 3jo, jude, rev
  const refLower = verseRef.toLowerCase();
  const ntPrefixes = ["matt","mar","luke","joh","act","rom","1co","2co","gal",
    "eph","php","col","1th","2th","1ti","2ti","tit","phm","heb","jas","1pe",
    "2pe","1jo","2jo","3jo","jude","rev"];
  const isNT = ntPrefixes.some((p) => refLower.startsWith(p));
  const lang = isNT ? "Greek (Koine)" : "Hebrew";

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 600,
    system: `You are a Biblical language scholar. When given a verse, identify 3-5 key ${lang} words
that unlock deeper meaning. For each word give:
- The English word from the verse
- Original ${lang} word (with transliteration)
- Strong's number
- Literal meaning
- One sentence on why it matters

Format your response as plain readable text (not JSON), using this pattern for each word:

**[English word]** — [Original word] ([transliteration], Strong's #XXXX)
Literal: [literal meaning]
Why it matters: [one warm, accessible sentence]

Keep the total response under 500 words. Warm, non-intimidating tone.`,
    messages: [{
      role: "user",
      content: `${verseRef}: "${verseText}"`
    }]
  });

  const answer = (response.content[0] as any).text;
  return { answer, remaining: usage.remaining };
});

/**
 * Retroactively checks and awards verse-count badges the onCreate trigger may
 * have missed (e.g. verses added before function was deployed).
 * Safe to call multiple times — skips already-earned badges.
 */
export const checkVerseBadges = functions.https.onCall(async (_reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  const uid = context.auth.uid;

  const versesSnap = await db
    .collection("memoryVerses")
    .doc(uid)
    .collection("verses")
    .get();
  const count = versesSnap.size;

  const badgesToCheck: Array<{ id: string; name: string; threshold: number }> = [
    { id: "first_verse", name: "First Verse", threshold: 1 },
    { id: "ten_verses",  name: "Ten Verses",  threshold: 10 },
  ];

  const awarded: string[] = [];

  for (const badge of badgesToCheck) {
    if (count < badge.threshold) continue;
    const ref = db.collection("badges").doc(uid).collection("earned").doc(badge.id);
    const snap = await ref.get();
    if (snap.exists) continue; // already earned

    const userSnap = await db.collection("users").doc(uid).get();
    const xp = (userSnap.data()?.profile?.xp as number) ?? 0;
    await ref.set({
      earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      name: badge.name,
      xpAtEarning: xp,
    });
    awarded.push(badge.id);
  }

  return { awarded, verseCount: count };
});

// ── HTTPS Callable: Search Verses ────────────────────────────────────────────

/**
 * Full-text keyword search across all Bible verses for a given version.
 * Uses collectionGroup('verses') + server-side JS includes() filtering since
 * Firestore does not support native substring/full-text search.
 *
 * Input:  { version: string, query: string }
 * Output: { results: Array<{ book, chapter, verse, reference, text }> }
 */
export const searchVerses = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (reqData, _context) => {
    const raw = (reqData ?? {}) as { version?: string; query?: string };
    const version = (raw.version ?? "kjv").trim().toLowerCase();
    const query = (raw.query ?? "").trim().toLowerCase();

    if (query.length < 3) {
      throw new functions.https.HttpsError("invalid-argument", "Query must be at least 3 characters");
    }

    // Use document ID ordering to restrict collectionGroup to just this version's path.
    // startAt/endAt on __name__ lets Firestore pre-filter without scanning other versions.
    const pathPrefix = `bible/${version}/`;
    const pathEnd = `bible/${version}/`;

    const snap = await db
      .collectionGroup("verses")
      .orderBy(admin.firestore.FieldPath.documentId())
      .startAt(pathPrefix)
      .endAt(pathEnd)
      .limit(40000)
      .get();

    const results: Array<{
      book: string;
      chapter: number;
      verse: number;
      reference: string;
      text: string;
    }> = [];

    for (const doc of snap.docs) {
      const data = doc.data();
      const text: string = data.text ?? data.verseText ?? "";
      if (!text.toLowerCase().includes(query)) continue;

      // Path: bible/{version}/books/{book}/chapters/{chapter}/verses/{id}
      const segments = doc.ref.path.split("/");
      const book = data.bookId ?? segments[3] ?? "";
      const chapter = data.chapterNumber ?? parseInt(segments[5] ?? "0", 10);
      const verse = data.verseNumber ?? 0;
      const reference = data.reference ?? `${book} ${chapter}:${verse}`;

      results.push({ book, chapter, verse, reference, text });
      if (results.length >= 30) break;
    }

    return { results };
  });

// ── HTTPS Callable: Interpret Verse ──────────────────────────────────────────

export const interpretVerse = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText } = raw as { verseRef: string; verseText: string };

  if (!verseRef || !verseText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or verseText");
  }

  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  const usage = await checkAndIncrementAiUsage(uid, "interpretVerse");
  if (!usage.allowed) {
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  // Fetch user study level for tone calibration
  const userSnap = await db.collection("users").doc(uid).get();
  const studyLevel: StudyLevel = (userSnap.data()?.profile?.studyLevel as StudyLevel) ?? "growing";
  const levelInstructions = studyLevelInstructions(studyLevel);

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 600,
    system: `You are a Bible study assistant for Joshua's Crossing, a Christian church in Denison, TX.
Interpret Scripture through the lens of these core beliefs:
- The Bible is the infallible, Holy Spirit-inspired Word of God and the sole foundation for faith and practice.
- God is the all-powerful, all-knowing, personal, and loving Creator of the Universe.
- Jesus is God incarnate — fully God and fully man — who lived a perfect life, died on the cross for the sins of the world, rose on the third day, ascended to Heaven, and is coming back.
- Salvation comes by trusting in Jesus as Lord; every person is sinful by nature and entry to Heaven is through faith in Christ alone.
- Baptism by full immersion is a public declaration of faith, not a requirement for salvation.
- The Church is the bride of Christ; every believer needs a church community.
- At death, every person goes to one of two eternal destinations: Heaven (with God) or Hell (apart from Him).
Give a concise verse interpretation (3-5 sentences) covering: (1) the plain meaning, (2) theological significance, (3) a brief application.
${levelInstructions}
Be warm, clear, and encouraging.`,
    messages: [{
      role: "user",
      content: `Interpret this verse:\n\n${verseRef} — "${verseText}"`
    }]
  });

  const answer = (response.content[0] as { type: "text"; text: string }).text;
  return { answer, remaining: usage.remaining };
});

// ── HTTPS Callable: Deep Study ────────────────────────────────────────────────

export const deepStudyVerse = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText } = raw as { verseRef: string; verseText: string };

  if (!verseRef || !verseText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or verseText");
  }

  const uid = context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const usage = await checkAndIncrementAiUsage(uid, "deepStudyVerse");
  if (!usage.allowed) {
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const studyLevel: StudyLevel = (userSnap.data()?.profile?.studyLevel as StudyLevel) ?? "growing";
  const levelInstructions = studyLevelInstructions(studyLevel);

  // Determine language (Greek for NT, Hebrew for OT)
  const refLower = verseRef.toLowerCase();
  const ntPrefixes = ["matt","mar","luke","joh","act","rom","1co","2co","gal",
    "eph","php","col","1th","2th","1ti","2ti","tit","phm","heb","jas","1pe",
    "2pe","1jo","2jo","3jo","jude","rev"];
  const lang = ntPrefixes.some((p) => refLower.startsWith(p)) ? "Greek (Koine)" : "Hebrew";

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 2000,
    system: `You are a Bible scholar for Joshua's Crossing, a Christian church in Denison, TX.
Ground all study content in these core beliefs:
- The Bible is the infallible, Holy Spirit-inspired Word of God — the only foundation for faith and practice.
- God is the all-powerful, all-knowing, personal, and loving Creator.
- Jesus is God incarnate — fully God and fully man — who died for the sins of the world, rose on the third day, ascended to Heaven, and is returning.
- Salvation is by faith in Jesus as Lord alone; humans are sinful by nature and cannot earn Heaven.
- Baptism by full immersion is a public declaration of new faith, not a requirement for salvation.
- The Church is the bride of Christ; community with other believers is essential.
- Eternity is real: Heaven for those who trust in Jesus, Hell for those who do not.
${levelInstructions}
Always respond with valid JSON only — no markdown fences, no extra text.`,
    messages: [{
      role: "user",
      content: `Generate a deep Bible study for this passage:

${verseRef}: "${verseText}"
Original language: ${lang}

Return ONLY this JSON structure:
{
  "verseClarity": {
    "context": "2-4 sentences explaining the historical, narrative, or literary context of this verse — who wrote it, to whom, and what was happening",
    "meaning": "3-5 sentences on the theological meaning of this specific verse — what it says about God, humanity, or salvation. Reference other parts of Scripture where helpful."
  },
  "wordStudy": [
    {
      "word": "English word from the verse",
      "originalWord": "${lang} word (use actual script if possible)",
      "transliteration": "phonetic transliteration",
      "strongsNumber": "H#### or G####",
      "definition": "1-2 sentence definition of the original word's core meaning",
      "scholarsInsight": "2-3 sentences connecting the word's original meaning to the theological significance in this passage"
    }
  ],
  "theologicalInsight": {
    "title": "Short doctrine or theme title (e.g. 'Providence: God's Sovereign Care')",
    "body": "3-4 sentences explaining the key theological doctrine or insight this verse teaches, grounded in the belief that Scripture is infallible, Jesus is the only path to salvation, and God is personal and loving",
    "scripturalSupport": [
      { "reference": "Book X:Y", "note": "One sentence on how this verse supports the insight" },
      { "reference": "Book X:Y", "note": "One sentence on how this verse supports the insight" },
      { "reference": "Book X:Y", "note": "One sentence on how this verse supports the insight" }
    ],
    "intellectualTakeaway": "One crisp sentence summarizing the deepest intellectual/theological takeaway from this verse"
  }
}

Include 2-4 key words in wordStudy. Pick the most theologically significant words.`
    }]
  });

  const raw2 = (response.content[0] as { type: "text"; text: string }).text.trim();
  const cleaned = raw2.replace(/^```json\n?/, "").replace(/^```\n?/, "").replace(/\n?```$/, "").trim();
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  const parsed = JSON.parse(cleaned.substring(start, end + 1));
  return { ...parsed, remaining: usage.remaining };
});

// ── Dig Deeper: Generate Study ────────────────────────────────────────────────

export const generateDigDeeperStudyFn = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  const uid = context.auth.uid;

  // Pro check — verify active subscription in Firestore
  const userDoc = await db.collection("users").doc(uid).get();
  const isPro = userDoc.data()?.isPro === true;
  if (!isPro) {
    throw new functions.https.HttpsError("permission-denied", "Dig Deeper Pro required");
  }

  const req = reqData as DigDeeperStudyRequest;

  // Validate all fields used in the cache key and AI prompt
  if (!req.bookId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing bookId");
  }
  if (!req.chapter) {
    throw new functions.https.HttpsError("invalid-argument", "Missing chapter");
  }
  if (!req.method) {
    throw new functions.https.HttpsError("invalid-argument", "Missing method");
  }
  if (!req.version) {
    throw new functions.https.HttpsError("invalid-argument", "Missing version");
  }
  if (!req.passageText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing passageText");
  }

  // Cache key includes version — KJV and NIV produce different content for the same passage.
  // For word study (Dig In from reader), include verseRef so each verse gets its own cache entry.
  const safeRef = req.verseRef
    ? req.verseRef.replace(/[\s:]/g, "_")
    : req.chapter.toString();
  const cacheKey = `${req.bookId}_${safeRef}_${req.method}_${req.version}`;
  const cacheRef = db.collection("digDeeperStudyCache").doc(uid).collection("sessions").doc(cacheKey);

  const cached = await cacheRef.get();
  if (cached.exists) {
    const d = cached.data()!;
    const age = Date.now() - (d.cachedAt as admin.firestore.Timestamp).toMillis();
    if (age < 7 * 24 * 60 * 60 * 1000) {
      return d.study; // Cache hit — no rate limit charge, no Claude call
    }
  }

  // Rate limit: max 80 new AI study generations per 30-day rolling window per user.
  // Cached responses (above) are free and don't count against this limit.
  const rateLimitRef = db.collection("users").doc(uid).collection("rateLimits").doc("studyGen");
  const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
  try {
    await db.runTransaction(async (tx) => {
      const rl = await tx.get(rateLimitRef);
      if (!rl.exists) {
        tx.set(rateLimitRef, { count: 1, windowStart: admin.firestore.Timestamp.now() });
        return;
      }
      const data = rl.data()!;
      const windowAge = Date.now() - (data.windowStart as admin.firestore.Timestamp).toMillis();
      if (windowAge > thirtyDaysMs) {
        // 30-day window has elapsed — reset
        tx.set(rateLimitRef, { count: 1, windowStart: admin.firestore.Timestamp.now() });
        return;
      }
      if (data.count >= 80) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "You've reached the 80 AI study limit for this 30-day period. Your limit resets 30 days after your first study this period."
        );
      }
      tx.update(rateLimitRef, { count: admin.firestore.FieldValue.increment(1) });
    });
  } catch (err) {
    if (err instanceof functions.https.HttpsError) throw err;
    functions.logger.error("Rate limit transaction error", { uid, err });
    // Don't block the user if the rate limit check itself fails
  }

  let study: DigDeeperStudyResponse;
  try {
    study = await generateDigDeeperStudy(req);
  } catch (err) {
    functions.logger.error("generateDigDeeperStudy error", { uid, bookId: req.bookId, chapter: req.chapter, method: req.method, err });
    throw new functions.https.HttpsError("internal", "Failed to generate study");
  }

  // Fire-and-forget cache write — don't fail the request if caching fails
  cacheRef.set({
    study,
    cachedAt: admin.firestore.FieldValue.serverTimestamp(),
  }).catch((err) => {
    functions.logger.error("Failed to cache study", { uid, cacheKey, err });
  });

  return study;
});

// ── Dig Deeper: Ask Question ──────────────────────────────────────────────────

export const askDigDeeperQuestionFn = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  // Pro check — verify active subscription in Firestore
  const uid = context.auth.uid;
  const userDoc = await db.collection("users").doc(uid).get();
  const isPro = userDoc.data()?.isPro === true;
  if (!isPro) {
    throw new functions.https.HttpsError("permission-denied", "Dig Deeper Pro required");
  }

  const { question, passage, passageText, history } = reqData as {
    question: string;
    passage: string;
    passageText: string;
    history: Array<{ role: string; content: string }>;
  };

  if (!question || !passage) {
    throw new functions.https.HttpsError("invalid-argument", "Missing question or passage");
  }

  const answer = await askDigDeeperQuestion(question, passage, passageText ?? "", history ?? []);
  return { answer };
});

// ── Dig Deeper: Notes AI Insights ────────────────────────────────────────────

export const getNotesInsightsFn = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  const uid = context.auth.uid;
  const userDoc = await db.collection("users").doc(uid).get();
  const isPro = userDoc.data()?.isPro === true;
  if (!isPro) {
    throw new functions.https.HttpsError("permission-denied", "Dig Deeper Pro required");
  }

  const { notes } = reqData as {
    notes: Array<{ title: string; type: string; content?: string; passage?: string; speaker?: string }>;
  };

  if (!notes || notes.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "No notes provided");
  }

  const client = getClaudeClient();

  const notesSummary = notes
    .map((n, i) => {
      const parts = [`${i + 1}. [${n.type}] "${n.title}"`];
      if (n.passage) parts.push(`   Passage: ${n.passage}`);
      if (n.speaker) parts.push(`   Speaker: ${n.speaker}`);
      if (n.content) parts.push(`   "${n.content.slice(0, 300)}${n.content.length > 300 ? '…' : ''}"`);
      return parts.join('\n');
    })
    .join('\n\n');

  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 700,
    system: `You are a thoughtful Bible study companion. Analyze a user's study notes and identify spiritual themes, patterns, and growth. Be encouraging and specific.

Note types in the data:
- "manual" = personal reflection note
- "aiStudy" = AI-guided study session on a passage
- "sermon" = sermon notes
- "question" = an open theological question the user is still working through

Pay special attention to notes of type "question" — these represent unresolved questions the user is wrestling with. In the suggestedNext field, if there are any open questions, connect one of them to a relevant passage or recent study topic from their other notes. If there are no open questions, suggest what to explore next based on study patterns as usual.

Respond in JSON with keys: themes (array of 3 strings, each a short theme name), summary (2-3 sentence narrative about their study journey), growthArea (one sentence on what stands out about their spiritual focus), suggestedNext (one sentence — if they have open questions, reference one and point toward a study that might address it; otherwise suggest a natural next passage or topic).`,
    messages: [
      {
        role: "user",
        content: `Here are my Bible study notes:\n\n${notesSummary}\n\nPlease analyze these and give me insights about my study journey.`,
      },
    ],
  });

  const raw = (response.content[0] as { text: string }).text.trim();
  const jsonMatch = raw.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new functions.https.HttpsError("internal", "Failed to parse insights");
  return JSON.parse(jsonMatch[0]);
});

// ── Dig Deeper: Deliver Pro (StoreKit 2 JWS transaction verification) ────────
//
// Flutter's in_app_purchase_storekit plugin defaults to StoreKit 2 as of v0.4.x
// on iOS 15+. That means purchase.verificationData.serverVerificationData is a
// signed JWS transaction token, NOT the old base64 App Store receipt — so it
// can never be validated against the legacy /verifyReceipt endpoint (that
// always fails with status 21002, "malformed receipt-data", regardless of
// whether the IAP products have been approved in App Store Connect).
//
// We verify the JWS directly using Apple's official server library, which
// checks the signature against Apple's root CAs and decodes the transaction
// payload (productId, expiresDate, revocationDate, etc.) without ever calling
// out to /verifyReceipt.

const DIGDEEPER_PRODUCT_IDS = new Set(["digdeeper_pro_monthly", "digdeeper_pro_yearly"]);
const DIGDEEPER_BUNDLE_ID = "com.derekdalton.digdeeper";
const DIGDEEPER_APPLE_ID = 6785735410; // numeric App Store ID — required for the Production verifier only

let _sandboxVerifier: SignedDataVerifier | undefined;
let _productionVerifier: SignedDataVerifier | undefined;

function loadAppleRootCAs(): Buffer[] {
  // Root certs downloaded from https://www.apple.com/certificateauthority/
  // and committed to functions/certs/ (see functions/certs/README.md).
  const certsDir = path.join(__dirname, "..", "certs");
  const files = fs.readdirSync(certsDir).filter((f) => f.endsWith(".cer"));
  if (files.length === 0) {
    throw new Error(
      `No Apple root CA certs found in ${certsDir}. Download AppleRootCA-G3.cer ` +
      "from https://www.apple.com/certificateauthority/ and place it there before deploying."
    );
  }
  return files.map((f) => fs.readFileSync(path.join(certsDir, f)));
}

function getVerifier(environment: Environment): SignedDataVerifier {
  const isProduction = environment === Environment.PRODUCTION;
  if (isProduction) {
    if (!_productionVerifier) {
      _productionVerifier = new SignedDataVerifier(
        loadAppleRootCAs(),
        true, // enableOnlineChecks — perform Apple revocation checking
        Environment.PRODUCTION,
        DIGDEEPER_BUNDLE_ID,
        DIGDEEPER_APPLE_ID
      );
    }
    return _productionVerifier;
  }
  if (!_sandboxVerifier) {
    _sandboxVerifier = new SignedDataVerifier(
      loadAppleRootCAs(),
      true,
      Environment.SANDBOX,
      DIGDEEPER_BUNDLE_ID
    );
  }
  return _sandboxVerifier;
}

interface VerifiedTransaction {
  productId: string;
  expiresDateMs: number;
  revoked: boolean;
}

/**
 * Verifies a StoreKit 2 signed transaction JWS against Apple's root certs.
 * Tries Production first, then Sandbox (mirrors the old prod->sandbox
 * fallback pattern from /verifyReceipt) since the same client build can hand
 * us either depending on whether the purchase came from TestFlight/sandbox
 * or the live App Store. Returns null if verification fails in both.
 */
async function verifyStoreKit2Transaction(signedTransactionInfo: string): Promise<VerifiedTransaction | null> {
  for (const env of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const verifier = getVerifier(env);
      const payload = await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
      console.log(
        `[verifyStoreKit2Transaction] verified via ${env}: productId=${payload.productId} ` +
        `expiresDate=${payload.expiresDate} revocationDate=${payload.revocationDate}`
      );
      return {
        productId: payload.productId ?? "",
        expiresDateMs: payload.expiresDate ?? 0,
        revoked: payload.revocationDate != null,
      };
    } catch (err) {
      console.log(`[verifyStoreKit2Transaction] ${env} verification failed: ${err}`);
      // try the other environment
    }
  }
  console.error("[verifyStoreKit2Transaction] verification failed in both Production and Sandbox");
  return null;
}

export const deliverDigDeeperProFn = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  const uid = context.auth.uid;
  const raw = (reqData as any).data ?? (reqData as any).body?.data ?? reqData ?? {};
  const receiptData = raw.receiptData as string | undefined;

  if (!receiptData) {
    throw new functions.https.HttpsError("invalid-argument", "Missing receiptData");
  }

  const isRestore = (raw.isRestore as boolean) ?? false;
  console.log(`[deliverDigDeeperProFn] verifying ${isRestore ? "restore" : "new purchase"} for uid=${uid}`);

  const result = await verifyStoreKit2Transaction(receiptData.trim());

  if (!result) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Could not verify this purchase with Apple. Please try again, or contact support if this persists."
    );
  }
  if (!DIGDEEPER_PRODUCT_IDS.has(result.productId)) {
    throw new functions.https.HttpsError("permission-denied", `Unrecognized product: ${result.productId}`);
  }
  if (result.revoked) {
    throw new functions.https.HttpsError("permission-denied", "This purchase was refunded or revoked.");
  }
  if (result.expiresDateMs <= Date.now()) {
    throw new functions.https.HttpsError("permission-denied", "Subscription is not active.");
  }

  console.log(
    `[deliverDigDeeperProFn] verified ✓ uid=${uid} product=${result.productId} ` +
    `expires=${new Date(result.expiresDateMs).toISOString()}`
  );

  // Write via admin SDK — bypasses Firestore rules (client cannot write isPro directly)
  await db.collection("users").doc(uid).set(
    { isPro: true, isPremium: true },
    { merge: true }
  );

  return { success: true };
});

// Deletes a Dig Deeper user's account and associated data (Apple Guideline 5.1.1(v)).
// Uses the Admin SDK so it does NOT require a freshly-reauthenticated client session —
// the caller's verified ID token (context.auth) is sufficient authorization to delete
// their own uid's data and Auth account.
export const deleteDigDeeperAccountFn = functions.https.onCall(async (_reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }
  const uid = context.auth.uid;
  console.log(`[deleteDigDeeperAccountFn] deleting account for uid=${uid}`);

  // Recursively delete every top-level doc keyed by uid (doc + all subcollections)
  const uidKeyedPaths = [
    `users/${uid}`,
    `digdeeperBadges/${uid}`,
    `userPlans/${uid}`,
    `notes/${uid}`,
    `highlights/${uid}`,
    `digDeeperStudyCache/${uid}`,
  ];
  for (const p of uidKeyedPaths) {
    try {
      await db.recursiveDelete(db.doc(p));
    } catch (err) {
      console.error(`[deleteDigDeeperAccountFn] failed to delete ${p}:`, err);
    }
  }

  // Best-effort: drop this uid from any shared partner reading plans
  try {
    const partnerPlansSnap = await db.collection("partnerPlans")
      .where("memberUids", "array-contains", uid).get();
    for (const doc of partnerPlansSnap.docs) {
      await doc.ref.update({
        memberUids: admin.firestore.FieldValue.arrayRemove(uid),
      });
    }
  } catch (err) {
    console.error("[deleteDigDeeperAccountFn] failed to clean up partnerPlans:", err);
  }

  // Best-effort: remove any partner invite links this user created
  try {
    const partnerLinksSnap = await db.collection("partnerLinks")
      .where("ownerUid", "==", uid).get();
    for (const doc of partnerLinksSnap.docs) {
      await doc.ref.delete();
    }
  } catch (err) {
    console.error("[deleteDigDeeperAccountFn] failed to clean up partnerLinks:", err);
  }

  // Finally, delete the Firebase Auth account itself
  await admin.auth().deleteUser(uid);

  console.log(`[deleteDigDeeperAccountFn] deleted account for uid=${uid}`);
  return { success: true };
});
