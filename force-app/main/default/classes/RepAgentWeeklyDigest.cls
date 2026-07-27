/**
 * Native, self-contained weekly "Rep Support Agent" question digest.
 * Reads the agent's own conversation data from the Agentforce analytics DMOs
 * (ssot__AiAgentInteractionMessage__dlm — Output messages carry the agent's
 * 'Confidence: N%' marker, which uniquely identifies this agent's answers),
 * buckets the questions into topics, renders an HTML digest, and emails the
 * trade-desk managers from the no-reply@ org-wide address. Runs on the Salesforce
 * scheduler (weekly). No external process.
 *
 * Schedule once:   System.schedule('Rep Support Weekly Digest','0 0 8 ? * MON *', new RepAgentWeeklyDigest());
 * Preview render:  RepAgentWeeklyDigest.sendSample('you@tastytrade.com');
 */
public with sharing class RepAgentWeeklyDigest implements Schedulable {

    static final List<String> RECIPIENTS = new List<String>{
        'quentin.dooley@tastytrade.com','nick.novoa@tastytrade.com','jason.chiou@tastytrade.com'};
    static final String OWA_ADDRESS = 'no-reply@tastytrade.com';
    static final Integer LOW_CONF = 40;
    static final Integer DAYS = 7;

    // Ordered specific -> general. {label, case-insensitive regex}
    static final List<List<String>> TOPICS = new List<List<String>>{
        new List<String>{'PDT (Pattern Day Trading)','pdt|pattern day'},
        new List<String>{'Good Faith Violations','good faith|gfv'},
        new List<String>{'Special Memorandum Account (SMA)','special memorandum|\\bsma\\b'},
        new List<String>{'Escheatment','escheat'},
        new List<String>{'Maintenance / Margin Calls','margin call|maintenance call|rm call|fm call|day trade call|maintenance excess|liquidat|past.?due'},
        new List<String>{'Margin / Buying Power / Reg-T','buying power|reg-?t|regulation t|pnr|epr|concentrat|margin requirement|margin is required|overnight requirement'},
        new List<String>{'Futures Enablement','enable futures|futures for|the works|futures approval'},
        new List<String>{'Options — Spreads / Strategy / Greeks','put spread|call spread|credit spread|vertical|max loss|greeks|iron condor|strangle|straddle'},
        new List<String>{'Options — Expiration / Assignment','assign|exercis|expir|itm|otm|settlement|pin risk|closing only'},
        new List<String>{'Stop / Order Triggers','stop order|stop.?loss|order got triggered'},
        new List<String>{'Circuit Breakers / Halts','circuit breaker|halt|luld'},
        new List<String>{'Dividends','dividend'},
        new List<String>{'Market Data / Quotes','market data|delayed quote|real-?time quote'},
        new List<String>{'Interest / Debit Balances','\\binterest\\b|debit balance'},
        new List<String>{'Funding — Wires','wire|swift|iban'},
        new List<String>{'Funding — ACH / Deposits / Withdrawals','ach|deposit|withdraw|link.*bank|bank account|available funds|money movement'},
        new List<String>{'ACATS / Account Transfers','acat|transfer.*account|dtc|internal transfer'},
        new List<String>{'Account Opening — Entity/LLC/Trust/IRA','llc|entity|trust|\\bira\\b|corporate|partnership'},
        new List<String>{'Account Opening / Closing / Restrictions','open.*account|create.*account|clos.*account|restrict|suspend|verif'},
        new List<String>{'Tax / 1099 / Cost Basis','1099|tax|cost basis|wash sale'},
        new List<String>{'International / Non-resident / Docs','non-?us|non resident|foreign|w-?8|withhold|international|address proof'},
        new List<String>{'Login / 2FA / Account Access','login|log in|2fa|two.?factor|password|locked|authenticat|security question'},
        new List<String>{'Compliance / Procedures','cursed|abusive|high commission|churning|supervision|complaint'},
        new List<String>{'Language Support (Spanish)','spanish|espanol|palabra'},
        new List<String>{'Crypto','crypto|bitcoin|\\bbtc\\b|\\beth\\b|stablecoin'},
        new List<String>{'Statements / Confirmations / Activity','statement|confirmation|activity|realized'}
    };
    static final String OTHER = 'Other / General';

    public class TopicStat { public String label; public Integer total=0; public Integer low=0; }
    public class Agg { public Integer total=0; public Integer low=0; public Map<String,TopicStat> byTopic=new Map<String,TopicStat>(); }

    // ---- entry points ------------------------------------------------------
    public void execute(SchedulableContext sc) { sendDigest(RECIPIENTS, false, null); }
    public static void run() { sendDigest(RECIPIENTS, false, null); }
    public static void sendSample(String toEmail) { sendDigest(new List<String>{toEmail}, true, null); }

    public static void sendDigest(List<String> recipients, Boolean sampleMode, List<String> ccList) {
        Agg a = sampleMode ? sampleAgg() : realAgg();
        String html = buildHtml(a, sampleMode);
        sendEmail(recipients, ccList, html);
    }

    // ---- aggregation from the Agentforce conversation DMOs ------------------
    static Pattern CONF = Pattern.compile('(?i)Confidence:\\s*(\\d{1,3})%');
    static Agg realAgg() {
        Datetime since = Datetime.now().addDays(-DAYS);
        // our agent's answers = Output messages carrying the Confidence marker
        List<ssot__AiAgentInteractionMessage__dlm> outs = [
            SELECT ssot__ContentText__c, ssot__ParentMessageId__c
            FROM ssot__AiAgentInteractionMessage__dlm
            WHERE ssot__AiAgentInteractionMessageType__c = 'Output'
              AND ssot__ContentText__c LIKE '%Confidence:%'
              AND ssot__MessageSentTimestamp__c >= :since
            LIMIT 5000];
        // paired questions (Input) keyed by Id for topic bucketing
        List<ssot__AiAgentInteractionMessage__dlm> ins = [
            SELECT Id, ssot__ContentText__c
            FROM ssot__AiAgentInteractionMessage__dlm
            WHERE ssot__AiAgentInteractionMessageType__c = 'Input'
              AND ssot__MessageSentTimestamp__c >= :since
            LIMIT 5000];
        Map<String,String> q = new Map<String,String>();
        for (ssot__AiAgentInteractionMessage__dlm m : ins) q.put(m.Id, m.ssot__ContentText__c);

        Agg a = new Agg();
        for (ssot__AiAgentInteractionMessage__dlm m : outs) {
            String ans = m.ssot__ContentText__c;
            Matcher mm = CONF.matcher(ans == null ? '' : ans);
            Integer conf = mm.find() ? Integer.valueOf(mm.group(1)) : 75;
            String question = q.get(m.ssot__ParentMessageId__c);
            bump(a, topicOf((question==null?'':question) + ' ' + (ans==null?'':ans)), conf < LOW_CONF);
        }
        return a;
    }
    static String topicOf(String text) {
        String t = (text==null?'':text);
        for (List<String> row : TOPICS) if (Pattern.compile('(?i)'+row[1]).matcher(t).find()) return row[0];
        return OTHER;
    }
    static void bump(Agg a, String topic, Boolean isLow) {
        a.total++; if (isLow) a.low++;
        TopicStat s = a.byTopic.get(topic);
        if (s==null){ s=new TopicStat(); s.label=topic; a.byTopic.put(topic,s); }
        s.total++; if (isLow) s.low++;
    }

    // ---- illustrative sample (approved distribution) for previews ----------
    static Agg sampleAgg() {
        Agg a = new Agg();
        add(a,'Funding — ACH / Deposits / Withdrawals',27,5); add(a,'Maintenance / Margin Calls',22,1);
        add(a,'Margin / Buying Power / Reg-T',18,3);          add(a,'ACATS / Account Transfers',15,4);
        add(a,'Options — Expiration / Assignment',15,2);      add(a,'Statements / Confirmations / Activity',12,2);
        add(a,'Options — Spreads / Strategy / Greeks',8,5);   add(a,'Tax / 1099 / Cost Basis',6,0);
        add(a,'Good Faith Violations',6,0);                   add(a,'Account Opening — Entity/LLC/Trust/IRA',5,1);
        add(a,'Login / 2FA / Account Access',5,3);            add(a,'Special Memorandum Account (SMA)',2,2);
        return a;
    }
    static void add(Agg a, String label, Integer tot, Integer low){
        TopicStat s=new TopicStat(); s.label=label; s.total=tot; s.low=low; a.byTopic.put(label,s);
        a.total+=tot; a.low+=low;
    }

    // ---- HTML render (matches the approved design) -------------------------
    static String buildHtml(Agg a, Boolean sampleMode) {
        List<TopicStat> topics = new List<TopicStat>(a.byTopic.values());
        // sort by total desc (simple selection sort — small list)
        for (Integer i=0;i<topics.size();i++) for (Integer j=i+1;j<topics.size();j++)
            if (topics[j].total > topics[i].total){ TopicStat t=topics[i]; topics[i]=topics[j]; topics[j]=t; }

        Integer mx = 1; List<TopicStat> top = new List<TopicStat>();
        for (TopicStat s : topics) { if (s.label==OTHER) continue; if (top.size()<10){ top.add(s); if (s.total>mx) mx=s.total; } }

        String rows='';
        for (TopicStat s : top) {
            Integer pct = a.total==0?0:Integer.valueOf(Math.round(100.0*s.total/a.total));
            Integer w   = Integer.valueOf(Math.round(100.0*s.total/mx));
            rows += '<tr><td style="padding:6px 10px 6px 0;font-size:13px;color:#243b53;white-space:nowrap;">'+esc(s.label)+'</td>'
                 +  '<td style="width:55%;padding:6px 0;"><div style="background:#eef2f7;border-radius:4px;height:16px;"><div style="background:#2f6fed;height:16px;width:'+w+'%;border-radius:4px;"></div></div></td>'
                 +  '<td style="padding:6px 0 6px 10px;font-size:13px;font-weight:700;color:#0b1e3f;text-align:right;">'+pct+'%</td></tr>';
        }
        // gaps: topics with low>0, sorted by low desc, excl Other
        List<TopicStat> gaps = new List<TopicStat>();
        for (TopicStat s : topics) if (s.low>0 && s.label!=OTHER) gaps.add(s);
        for (Integer i=0;i<gaps.size();i++) for (Integer j=i+1;j<gaps.size();j++)
            if (gaps[j].low > gaps[i].low){ TopicStat t=gaps[i]; gaps[i]=gaps[j]; gaps[j]=t; }
        String gl='';
        for (Integer i=0;i<gaps.size() && i<6;i++) {
            TopicStat s=gaps[i]; Integer rate = s.total==0?0:Integer.valueOf(Math.round(100.0*s.low/s.total));
            String tag = rate>=50 ? (s.low+' of '+s.total+' &middot; <b>'+rate+'%</b>') : (s.low+' shaky');
            gl += '<li style="margin:5px 0;font-size:13px;color:#5b3a00;">'+esc(s.label)+' &nbsp;<span style="color:#a15c00;">('+tag+')</span></li>';
        }
        if (gl=='') gl = '<li style="font-size:13px;color:#8a6a3a;">No low-confidence answers this week.</li>';

        String banner = sampleMode ? '<div style="font-size:12px;color:#66788f;background:#e9edf3;padding:8px 14px;border-radius:6px;margin-bottom:10px;">Preview of the automated weekly digest &mdash; built from recent real rep questions. Feedback welcome &rarr; Barrett.</div>' : '';
        String empty  = a.total==0 ? '<div style="font-size:13px;color:#829ab1;padding:8px 0;">No agent questions logged in the last '+DAYS+' days.</div>' : '';

        return banner
          + '<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:640px;margin:0 auto;background:#f4f6fa;padding:16px;">'
          + '<div style="background:#0b1e3f;color:#fff;padding:22px 26px;border-radius:10px 10px 0 0;"><div style="font-size:19px;font-weight:700;">Rep Support Agent &mdash; Weekly Question Digest</div>'
          + '<div style="font-size:13px;color:#9fb3d1;margin-top:5px;">What frontline reps asked this week &mdash; and where the knowledge gaps are</div></div>'
          + '<div style="background:#fff;border:1px solid #e3e8ef;border-top:none;padding:22px 26px;">'
          + '<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;"><tr>'
          + tile(String.valueOf(a.total),'Questions','#0b1e3f','#f4f7fc') + '<td style="width:12px;"></td>'
          + tile(String.valueOf(a.total-a.low),'Answered Confidently','#1a7a3d','#eefaf0') + '<td style="width:12px;"></td>'
          + tile(String.valueOf(a.low),'Low-Confidence','#b5540a','#fff4e6') + '</tr></table>'
          + empty
          + '<div style="font-size:12px;font-weight:700;color:#334e68;text-transform:uppercase;letter-spacing:.6px;margin-bottom:8px;">Top 10 Topics &mdash; % of total questions</div>'
          + '<table width="100%" cellpadding="0" cellspacing="0">'+rows+'</table>'
          + '<div style="margin-top:22px;background:#fffaf0;border:1px solid #f2d9a8;border-left:4px solid #e8930c;border-radius:8px;padding:14px 18px;">'
          + '<div style="font-size:13px;font-weight:800;color:#8a4b00;margin-bottom:6px;">&#9888;&#65039; Biggest Training Gaps</div>'
          + '<div style="font-size:12px;color:#8a6a3a;margin-bottom:8px;">Where the agent &mdash; and likely the rep &mdash; was least confident:</div>'
          + '<ul style="margin:0;padding-left:18px;">'+gl+'</ul></div>'
          + '<div style="margin-top:20px;font-size:12px;color:#829ab1;line-height:1.5;border-top:1px solid #eef2f7;padding-top:14px;">'
          + 'Every low-confidence answer is auto-filed as a ticket on the <b>SK</b> Jira board so the gap gets worked. Questions or changes to this report &rarr; Barrett.<br>'
          + '<span style="color:#a8b8c8;">&mdash; Rep Support Agent (automated)</span></div></div></div>';
    }
    static String tile(String num, String label, String color, String bg) {
        return '<td style="text-align:center;padding:10px;background:'+bg+';border-radius:8px;"><div style="font-size:26px;font-weight:800;color:'+color+';">'+num+'</div>'
             + '<div style="font-size:11px;color:#627d98;text-transform:uppercase;letter-spacing:.5px;">'+label+'</div></td>';
    }
    static String esc(String s){ return s==null?'':s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;'); }

    // ---- send --------------------------------------------------------------
    static void sendEmail(List<String> recipients, List<String> ccList, String html) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(recipients);
        if (ccList != null && !ccList.isEmpty()) m.setCcAddresses(ccList);
        for (OrgWideEmailAddress o : [SELECT Id FROM OrgWideEmailAddress WHERE Address = :OWA_ADDRESS LIMIT 1])
            m.setOrgWideEmailAddressId(o.Id);
        m.setSubject('Rep Support Agent — Weekly Question Digest');
        m.setHtmlBody(html);
        m.setSaveAsActivity(false);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{m});
    }
}
