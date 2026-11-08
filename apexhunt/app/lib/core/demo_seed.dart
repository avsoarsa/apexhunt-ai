import 'models.dart';
import 'storage.dart';

/// Fictional sample data for store screenshots and UI demos.
/// Enabled only with `--dart-define=DEMO_SEED=true`; never in production builds.
class DemoSeed {
  static const enabled = bool.fromEnvironment('DEMO_SEED');

  static Future<void> apply(LocalStore store) async {
    if (!enabled || await store.readJson('profile.json') != null) return;
    final profile = MasterProfile(
      contact: Contact(name: 'Alex Rivera', email: 'alex@example.com', location: 'London, UK', links: ['github.com/alexrivera']),
      headline: 'Backend Engineer · Node.js & PostgreSQL',
      summary: 'Backend engineer building order and payments APIs.',
      roles: [
        WorkRole(id: 'r1', company: 'TechNova Solutions', title: 'Backend Engineer', start: '2023-02', location: 'London', bullets: [
          'Built REST APIs in Node.js for order processing and database updates.',
          'Maintained PostgreSQL schemas and reduced query latency by 25%.',
          'Containerised services with Docker and set up GitHub Actions CI.',
        ], skills: ['Node.js', 'TypeScript', 'PostgreSQL', 'Docker']),
        WorkRole(id: 'r2', company: 'Brightline Labs', title: 'Junior Developer', start: '2021-07', end: '2023-01', bullets: [
          'Shipped internal dashboards in React for the operations team.',
          'Wrote integration tests that caught billing bugs before release.',
        ], skills: ['React', 'JavaScript', 'Jest']),
      ],
      education: [Education(institution: 'University of Manchester', degree: 'B.Sc. Computer Science', year: '2021')],
      skills: ['Node.js', 'TypeScript', 'PostgreSQL', 'Docker', 'REST APIs', 'React', 'Git', 'GitHub Actions'],
      learning: ['Kafka'],
      targetRoles: ['Backend Engineer'],
    );
    await store.writeJson('profile.json', profile.toJson());
    await store.writeJson('mission_config.json', MissionConfig(countries: ['REMOTE', 'GB', 'DE'], keywords: ['Backend Engineer', 'Node.js Developer']).toJson());

    final opps = [
      Opportunity(id: 'demo:1', source: 'Remotive', title: 'Senior Backend Engineer (Node.js)', company: 'Fintech Co', location: 'Europe', remote: true, salary: '€70k–€85k', matchScore: 86, matchedTerms: ['Node.js', 'PostgreSQL', 'Docker', 'TypeScript'], description: 'We are hiring a backend engineer with Node.js, TypeScript, PostgreSQL, Docker, Kafka and AWS experience to build payment APIs.'),
      Opportunity(id: 'demo:2', source: 'Jobicy', title: 'Backend Developer — Payments', company: 'Paylane', location: 'UK', remote: true, matchScore: 74, matchedTerms: ['Node.js', 'REST APIs', 'PostgreSQL'], description: 'Node.js, REST APIs, PostgreSQL, Redis.'),
      Opportunity(id: 'demo:3', source: 'Remote OK', title: 'Full-Stack Engineer (React + Node)', company: 'Orbit Health', location: 'Worldwide', remote: true, salary: '\$90k–\$120k', matchScore: 69, matchedTerms: ['React', 'Node.js', 'TypeScript'], description: 'React, Node.js, TypeScript, GraphQL.'),
      Opportunity(id: 'demo:4', source: 'Freelancer.com', title: 'Build a REST API for a delivery app', company: 'Freelancer.com client', location: 'Remote', remote: true, salary: 'USD 750–1500', matchScore: 63, kind: MissionMode.freelance, matchedTerms: ['Node.js', 'PostgreSQL'], description: 'Need an Express + Postgres API.'),
    ];
    await store.writeJson('pipeline.json', opps.map((e) => e.toJson()).toList());

    final analysis = JdAnalysis(title: 'Senior Backend Engineer (Node.js)', company: 'Fintech Co', summary: 'Build and scale payment APIs on Node.js and PostgreSQL in an event-driven architecture.', requirements: [
      Requirement(skill: 'Node.js'),
      Requirement(skill: 'TypeScript'),
      Requirement(skill: 'PostgreSQL'),
      Requirement(skill: 'Docker'),
      Requirement(skill: 'REST APIs'),
      Requirement(skill: 'Kafka', evidence: 'experience with event streaming (Kafka)'),
      Requirement(skill: 'AWS', importance: Importance.nice),
    ], keywords: ['payment APIs', 'event-driven']);
    final artifact = TailoredArtifact(
      id: 'demo-artifact',
      opportunity: opps.first..status = 'TAILORED',
      analysis: analysis,
      decisions: {'Node.js': SkillDecision.matched, 'TypeScript': SkillDecision.matched, 'PostgreSQL': SkillDecision.matched, 'Docker': SkillDecision.matched, 'REST APIs': SkillDecision.matched, 'Kafka': SkillDecision.learning, 'AWS': SkillDecision.gap},
      cv: TailoredCv(
        headline: 'Backend Engineer · Node.js, TypeScript & PostgreSQL',
        summary: 'Backend engineer who builds order and payment APIs in Node.js and TypeScript, with hands-on PostgreSQL performance work and Dockerised CI/CD.',
        skills: ['Node.js', 'TypeScript', 'PostgreSQL', 'REST APIs', 'Docker', 'GitHub Actions', 'React', 'Git'],
        learning: ['Kafka'],
        roles: [
          TailoredRole(roleId: 'r1', bullets: [
            TailoredBullet(text: 'Built RESTful order-processing APIs in Node.js and TypeScript powering database updates for payments flows.', original: 'Built REST APIs in Node.js for order processing and database updates.', keywords: ['REST APIs', 'Node.js']),
            TailoredBullet(text: 'Tuned PostgreSQL schemas and queries, reducing query latency by 25%.', original: 'Maintained PostgreSQL schemas and reduced query latency by 25%.', keywords: ['PostgreSQL']),
            TailoredBullet(text: 'Containerised services with Docker and automated CI with GitHub Actions.', original: 'Containerised services with Docker and set up GitHub Actions CI.', keywords: ['Docker']),
          ]),
          TailoredRole(roleId: 'r2', bullets: [
            TailoredBullet(text: 'Wrote integration tests that caught billing bugs before release.', original: 'Wrote integration tests that caught billing bugs before release.', change: BulletChange.unchanged),
            TailoredBullet(text: 'Shipped internal dashboards in React for the operations team.', original: 'Shipped internal dashboards in React for the operations team.', change: BulletChange.unchanged),
          ]),
        ],
        metricPrompts: [
          {'role_id': 'r1', 'bullet': 'Built RESTful order-processing APIs…', 'question': 'Roughly how many orders per day did these APIs handle?'},
        ],
      ),
      atsBefore: 58,
      atsAfter: 84,
      applicationNote: 'Fintech Co needs payment APIs that stay fast under load — that is the work I do every day.\n\nAt TechNova I build the Node.js and TypeScript APIs behind order processing, and I cut PostgreSQL query latency by 25% by reworking schemas and indexes. I containerised our services with Docker and set up CI with GitHub Actions, so releases are boring in the best way.\n\nI have not run Kafka in production yet; I am learning it now and building an event-driven order pipeline as a side project.\n\nI would love to talk about how your team handles idempotency across payment events.',
      prep: PrepDossier(
        pitch: 'I am a backend engineer at TechNova, where I build the Node.js and TypeScript APIs behind order processing and keep our PostgreSQL fast — I cut query latency by 25%. Before that I shipped React dashboards and integration tests at Brightline Labs. I am looking for a team building payment systems at scale, which is why Fintech Co stood out.',
        stories: [
          StarStory(title: 'Cutting query latency by 25%', requirement: 'PostgreSQL', source: 'Backend Engineer @ TechNova Solutions', situation: 'Order lookups were slowing down as volume grew.', task: 'Find and fix the slow queries without downtime.', action: 'Profiled queries with EXPLAIN ANALYZE, added composite indexes and reshaped two hot tables. [your detail: how you rolled it out]', result: 'Query latency dropped 25%.'),
          StarStory(title: 'Catching billing bugs before release', requirement: 'Testing', source: 'Junior Developer @ Brightline Labs', situation: 'Billing regressions reached production twice in a quarter.', task: 'Add a safety net before release.', action: 'Wrote integration tests around invoice generation.', result: 'Caught billing bugs before release. [your detail: how many]'),
        ],
        questions: [
          QaCard(question: 'How do you make an API endpoint idempotent?', whyAsked: 'Payments retry; duplicates cost money.', answer: 'Idempotency keys stored with a unique constraint; return the original response on replay. Mention where you used unique constraints at TechNova.'),
          QaCard(question: 'Walk me through debugging a slow PostgreSQL query.', whyAsked: 'They need someone who can own database performance.', answer: 'EXPLAIN ANALYZE → spot seq scans → index or rewrite → verify in staging. Use your 25% latency story.'),
        ],
        gaps: [
          GapPlan(
            skill: 'Kafka',
            mentalModel: 'Kafka is a distributed, append-only log. Producers write events to partitioned topics; consumer groups read them independently, so services stay decoupled and can replay history.',
            honestAnswer: '“Not in production yet. I have built synchronous order APIs and I am learning Kafka now — I have a side project where order events flow through a topic with an idempotent consumer. I would ramp up fast because the hard parts — idempotency and ordering — are problems I already handle in Postgres.”',
            bridge: 'Your order-processing APIs and PostgreSQL work map directly to producers and idempotent consumers.',
            learnSteps: ['Run Kafka locally with Docker Compose', 'Produce order events from a tiny Node.js service (kafkajs)', 'Write a consumer group that stores orders idempotently in Postgres', 'Break it on purpose: kill a consumer and watch rebalancing'],
            vocabulary: ['Partition', 'Consumer group', 'Offset commit', 'Idempotent producer', 'Dead-letter queue'],
            practiceTask: 'Turn your order API into an event-driven pipeline and push it to GitHub.',
          ),
        ],
        questionsToAsk: ['How do you handle exactly-once processing across payment events today?', 'What does on-call look like for the payments team?'],
      ),
      engineLabel: 'Apex Pro',
      mastery: {'pitch': 2, 's0': 2},
    );
    await store.writeJson('artifacts.json', [artifact.toJson()]);
  }
}
