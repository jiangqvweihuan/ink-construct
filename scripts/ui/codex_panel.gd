extends CanvasLayer

## 图鉴 · 主菜单入口。
## 敌人 / 化身页使用角色卡与演示台；状态 / 故事页使用静态目录与长文详情。
## 交互一律点击：默认播待机动画；点下方招式 / 技能 / 动作按钮，演示台播该动作并把
## 来历 / 机制 / 数值 / 冷却写进解析面板；一条技能带多个变式（pool）时用 ↑ / ↓ 手动切换。
## 每个角色按词条分类；只有具备正式资料的被动才显示入口。
## 玩家文案与内部动画键、判定参数分离；没有正式来历的区块直接省略。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Skins = preload("res://scripts/systems/skins.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const EnemyTypes = preload("res://scripts/enemies/enemy_types.gd")
const SpinePoseMixer = preload("res://scripts/systems/spine_pose_mixer.gd")
const BossTypes = preload("res://scripts/enemies/boss_types.gd")
const StatusCodex = preload("res://scripts/ui/status_codex.gd")
const StoryCodex = preload("res://scripts/ui/story_codex.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")
const CODEX_MUSIC := "res://audio/music/codex_theme.mp3" # 图鉴曲《百相入卷》，进入图鉴时独占播放

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3) # 英雄级主角的金标

const TAB_ENEMY := 0
const TAB_FORM := 1
const TAB_STATUS := 2
const TAB_STORY := 3

## 敌人收录顺序：杂兵 → 精英 → Boss（Boss 追加在末尾，顺序按 boss_types.ROSTER）
const ENEMY_ORDER := ["c016", "c017", "c035", "c018", "c012", "c037"]

## 化身招式正式资料：顺序分别对应 attacks 与 hud_skills；按钮只展示正式名。
const FORM_ATTACK_TEXT := {
	"c021": [
		{"name": "绛衣试水", "num": "1 伤 ｜ 近身突进", "mech": "向前垫步刺出第一匕，造成 1 点伤害。", "lore": "她初学舞时，师父要她踩着浅水练步，裙摆不能沾湿。后来浅水换成了血，她仍先递出最轻的一刺，试试对方脚跟是否站稳。"},
		{"name": "回燕剪翎", "num": "1 伤 ｜ 近身突进", "mech": "紧接前式再进半步，以第二匕造成 1 点伤害。", "lore": "戏里的燕式要折腰回望，她将回望藏进第二匕。对手只看见红袖掠面，真正的刃已追着旧拍剪到身前。"},
		{"name": "红绫卷霜", "num": "2 段 × 1 伤 ｜ 前后横扫", "mech": "回身横扫，身前身后均可命中，两段各造成 1 点伤害。", "lore": "《夜奔》的末势原要连转两周，水袖扫过前后两盏灯。她收袖为刃，两圈仍照旧谱转完，只是如今灯下站的是敌手。"},
	],
	"c013": [
		{"name": "撞钟", "num": "2 伤 ｜ 前后挥击", "mech": "挥棒前撞，棒势同时顾及身后，造成 2 点伤害。", "lore": "破庙的晨钟裂了许多年，他仍以每天第一记挥棒替它报时。钟声未必远播，挡在钟前的人却都知道天亮了。"},
		{"name": "碎磐", "num": "3 伤 ｜ 前后挥击", "mech": "承上式沉棒重砸，前后均可命中，造成 3 点伤害。", "lore": "山洪夜，他用这一棒砸开堵住渡口的巨石。村民记住的是生路，他记住的是石裂时那声闷响，此后收势总要照那一下练。"},
	],
	"c023": [
		{"name": "疏枝引鹤", "num": "鞭击 2 伤 ｜ 前刺 3 伤 ｜ 首段拉回", "mech": "先以长鞭剑远程抽击，造成 2 点伤害并把敌人拉近，再踏步前刺造成 3 点伤害。", "lore": "她少年时折梅逗鹤，枝条先引得白鹤低头，再以一声清哨唤它近前。如今梅枝成了软剑，鹤不再来，被牵到剑前的只剩不肯低头的敌手。"},
	],
	"z000": [
		{"name": "松间问鹤", "num": "1 伤 ｜ 近身剑击", "mech": "向前递出快剑，造成 1 点伤害。", "lore": "守碑时，她每晨向松间白鹤问一剑，鹤不惊便算合格。如今她递出的第一剑仍不催命，只问来客是否真要把路走完。"},
		{"name": "流云回锋", "num": "1 伤 ｜ 前后剑击", "mech": "回锋续斩，身前身后均可命中，造成 1 点伤害。", "lore": "山风从不会只从一个方向来。她听风十年，学会让剑锋随云势折返；背后那一声脚步，往往比正面刀光更早招来这一剑。"},
		{"name": "骤雨听剑", "num": "4 段 × 1 伤 ｜ 每段晕眩 0.8 秒", "mech": "前后连续四斩，每段造成 1 点伤害并晕眩 0.8 秒，可打断正在起手的敌人。", "lore": "暴雨夜，她在碑前以剑尖接住四种雨声：穿松、打叶、落石、敲碑。四声连成一式，剑落如雨，挨剑的人连下一句喝问也说不完整。"},
		{"name": "玉宇挑月", "num": "2 伤 ｜ 击飞", "mech": "连段收尾向上挑剑，造成 2 点伤害并将敌人挑到空中，落地后短暂硬直。", "lore": "师父说剑碑最高处刻着一轮月，她信了多年，练到能挑落碑顶枯叶才看清那只是凿痕。月亮虽假，这一挑倒真能送人离尘。"},
	],
	"z002": [
		{"name": "冰弦初响", "num": "1 伤 ｜ 近身弦音", "mech": "拨响第一声短音，造成 1 点伤害。", "lore": "宫中教习说，名曲第一音要像冰面初裂，轻得几乎听不见，却教满座知道寒冬已至。她至今仍用这一声提醒来客：曲已经开始。"},
		{"name": "促柱追声", "num": "2 伤 ｜ 近身弦音", "mech": "移柱急拨，续前音造成 2 点伤害。", "lore": "旧宫宴上的舞步总比乐声急，她只得移柱催弦追赶。如今面前换作刀光，她仍不肯慢半拍，第二音总比敌人的念头先到。"},
		{"name": "急雨敲窗", "num": "2 伤 ｜ 近身弦音", "mech": "以骤促一拨承接连段，造成 2 点伤害。", "lore": "冷宫的窗纸经不起夜雨，她在那里练出这一声促音。雨点敲窗，弦音敲骨，门外的人常分不清哪一声更叫人心慌。"},
		{"name": "余音入魔", "num": "3 伤 ｜ 远程魔音 ｜ 癫狂 12 秒", "mech": "末段发出不可穿透的魔音，造成 3 点伤害并使命中者癫狂 12 秒；癫狂者会攻击距离自己最近的任意敌我目标。", "lore": "《黍离》曲终后，最后一个音本该散尽。城破那夜它却停在断梁之间，把每个人心底最不敢认的恨都唤了出来，从此再不肯安眠。"},
	],
	"z003": [
		{"name": "袖里青蛇", "num": "1 伤 ｜ 两种剑势", "mech": "以两种起手剑势之一近身刺击，造成 1 点伤害。", "lore": "他做药商伙计时嫌长剑挂腰吓跑主顾，偏要藏进袖里。一次山蛇从药篓探头，他受惊出剑，蛇没伤着，袖口倒裂了；掌柜骂了半月，这两式快剑却被他得意地留了下来。"},
		{"name": "揽月上霄", "num": "2 伤 ｜ 击飞", "mech": "第二式将敌人挑到空中，造成 2 点伤害，落地后短暂硬直。", "lore": "他年轻时与人赌一坛酒，夸口能把井里的月亮挑出来。剑尖入水，月影散了，人也浇了个透；第二日他改练上挑，酒仍未赢到，后来拦路的人却先替他飞上去看了看月。"},
		{"name": "断雁回风", "num": "3 伤 ｜ 两种收势", "mech": "以两种收势之一斩出连段终剑，造成 3 点伤害。", "lore": "他小时候被村口白鹅追咬过，长大后见雁阵折返仍心里发虚，抢先闭眼挥完三剑。雁没伤着，山口的盗旗倒断了。众人夸这招「断雁回风」，他受用地全认下来，至今没提过那只鹅。"},
	],
}

const FORM_SKILL_TEXT := {
	"c021": [
		{"name": "流光度影", "num": "2 伤 ｜ 路径贯穿 ｜ 全程无敌", "mech": "隐身向前穿刺，对路径上的敌人造成 2 点伤害；施展期间无敌，可穿过敌身。", "lore": "火场里，她背着孩子穿过一道将塌的灯廊，脚步比坠火还快。后来她独自行刺，仍沿那条看不见的旧路前进；红裙现身时，沿途只留一道冷光。"},
		{"name": "罗刹旋舞", "num": "4 段 × 2 伤 ｜ 每段 1 层流血 ｜ 全程无敌", "mech": "原地旋斩四周，四段各造成 2 点伤害并叠 1 层流血；每层每秒造成 1 伤，持续 5 秒，最多 5 层，新层刷新持续时间。", "lore": "她曾扮罗刹女压轴，四面彩旗围着她转，班主要求每面旗都得扫到。如今彩旗换成刀兵，她仍四面照拂，一处也不肯冷落。"},
		{"name": "红缨缚雁", "num": "2 伤 ｜ 定身 3 秒 ｜ 命中分裂", "mech": "后跃掷出双匕，造成 2 点伤害并使首个命中者定身 3 秒；命中后分裂一柄续飞匕首。定身只锁移动，敌人仍可出手。", "lore": "班中旧戏有掷缨擒雁一折，红绸离手，空中纸雁便要落地。她把绸结藏进匕柄，又把纸雁换成真正的追兵；第一柄认人，第二柄替她赶未尽的路。"},
	],
	"c013": [
		{"name": "钟荡群山", "num": "3 伤 ｜ 击退定身 2 秒 ｜ 护身 1 次", "mech": "第一棒横扫前后，造成 3 点伤害并击退；被击退者撞到同伴时双方各受 1 伤，落点定身 2 秒。收势展开金钟罩，8 秒内抵挡一次攻击。", "lore": "他在钟楼下扫雪，见老僧敲钟前总要先让众人退开。后来狼牙棒代替钟槌，一棒送出去的是人，留下来的那圈护光，才算给他自己的钟声。"},
		{"name": "金刚怒目", "num": "3 伤 ｜ 晕眩 2 秒", "mech": "重棒横击造成 3 点伤害并晕眩 2 秒；立即打断起手，使命中者不能移动也不能出手。", "lore": "他年轻时读经，只记得金刚怒目四字，以为怒便要多用三分力。三年后重棒落下，他终于明白真正的怒是不许恶事再做下去，而不是把眼前一切砸碎。"},
		{"name": "立地听禅", "num": "回血 2 ｜ 蓄力反伤 ｜ 起手霸体", "mech": "举棒蓄力约 3 秒，期间霸体且不受伤害，将来袭伤害原样反弹给攻击者；落棒恢复 2 点生命，不造成伤害。", "lore": "面壁第三年，檐雨、犬吠与骂声都成了同一种响动。他不再逐句回答，只把它们原样还给来处。等心里真正静下来，伤口反倒有了愈合的余地。"},
	],
	"c023": [
		{"name": "梅间回雪", "num": "持续每 0.5 秒 1 伤 ｜ 尾鞭 5 伤 ｜ 中毒 4 秒", "mech": "旋鞭期间每 0.5 秒横扫前后并造成 1 伤，最后远甩造成 5 伤；任意一击命中均使目标中毒 4 秒，每 0.5 秒失去 1 生命，不叠层，重复命中刷新时长。", "lore": "西岭春迟，梅花常被回雪压落。她偏要在花枝将折未折时旋剑，让花瓣重新飞起。毒随花香潜入伤处，最后一鞭才把人从这场错觉里惊醒。"},
	],
	"z000": [
		{"name": "千锋回雪", "num": "3 段 × 1 伤 ｜ 每段 1 层流血 ｜ 起手霸体", "mech": "旋剑连斩前后，三段各造成 1 点伤害并叠 1 层流血；每层每秒造成 1 伤，持续 5 秒，最多 5 层。", "lore": "天姥山初雪总被松枝切成碎白，她便以剑尖把每一片送回原处。三转剑光像雪复归枝，看似轻巧，落在血肉上却层层不肯消融。"},
		{"name": "月华斩", "num": "5 伤 ｜ 1 层流血 ｜ 起手霸体", "mech": "以两种剑势之一近身重斩，造成 5 点伤害并叠 1 层流血。", "lore": "剑碑无字的背面，只在月夜浮出一道淡痕。她守到第七年才挥剑照描，碑没有留下新字，山门外却多了一条至今未合的细缝。"},
		{"name": "步月登霄", "num": "3 伤 ｜ 高额击飞 ｜ 无视霸体", "mech": "踏身飞踢造成 3 点伤害并高高挑飞敌人，可击破霸体；落地后短暂硬直。", "lore": "她下山前问师父，若碑上的月永远够不到该如何。师父让她先踢开挡路的山门。这一脚由此得名：月未必肯近，挡路的人倒可以先上去。"},
		{"name": "一剑惊鸿", "num": "觉醒 12 秒 ｜ 命中叠剑意", "mech": "起手霸体，招式结束后觉醒 12 秒并解锁后续觉醒技；觉醒期间每次命中获得 1 层剑意，最多 5 层，每层使全部伤害 +1。", "lore": "有人问她剑谱为何没有首页，她说第一剑永远留给真正拔剑的那一刻。鸿影掠水只是一瞬，随后每一次命中，都是那一瞬在心口多留下的一笔。"},
		{"name": "剑奉山河", "num": "3 段 × 1 伤 ｜ 横斩 4 伤 ｜ 按总伤回血", "mech": "觉醒中可用。前三剑各晕眩 0.8 秒，随后横斩造成 4 伤、2 层流血并无视霸体远退；收剑恢复本招总伤害的 30% 生命，且 6 秒内全部伤害 +1。", "lore": "她见过山河最破败的样子，仍愿把最完整的一剑留给它。三剑问罪，一剑开路，最后合掌并非求神，只是提醒自己还有力气继续往前。"},
		{"name": "惊鸿燕返", "num": "2 伤 ｜ 小击飞 ｜ 命中返还 50% 冷却", "mech": "觉醒中可用。无敌翻滚向前穿身，末段踢击造成 2 点伤害并小幅击飞；命中立即返还本招 50% 冷却。", "lore": "山燕每年回碑前筑巢，从不因旧巢被风毁掉而迟疑。她学它翻身穿雨，也学它落地即返；这一脚若真踢中，便不必再等下一季春风。"},
	],
	"z002": [
		{"name": "踏弦", "num": "无敌 ｜ 穿身位移 ｜ 无伤害", "mech": "踏弦借势位移，施展期间无敌并可穿过敌身，不造成伤害。", "lore": "逃亡那夜，宫桥横索被刀兵斩断，她踩着颤动的弦索走过深池。如今脚下没有桥，她仍能借一声弦响借力，从刀光缝里从容退场。"},
		{"name": "黍离", "num": "穿透 3 伤 ｜ 癫狂至少 12 秒 ｜ 回血 2", "mech": "发出穿透魔音造成 3 伤；命中使目标癫狂剩余时长翻倍且至少为 12 秒，自身恢复 2 点生命。", "lore": "彼黍离离，彼稷之苗。她离宫时什么都没带，只把这句旧诗记在弦上。曲音穿过多少人，故国的恨便延续多久，而她靠这点旧痛活到今日。"},
		{"name": "摄心", "num": "未觉醒：单体魅惑 ｜ 觉醒：全房 1 伤", "mech": "未觉醒时魅惑正前方首个敌人，杂兵 15 秒、精英 10 秒、首领 5 秒；非首领回满生命并转为自己一方、不再攻击执卷者，执卷者对其伤害减半并向上取整。觉醒后化为「众生同狂」：蓄力无敌，全房造成 1 伤并施加造成伤害翻倍的强化癫狂。", "lore": "御前献艺时，她能用一声慢板教君王放下酒杯，也能用一声急弦叫武将回头。真正摄心的从来不是妖法，只是她替每个人弹出了最不敢听的那一段。"},
		{"name": "红尘劫", "num": "觉醒 8 秒 ｜ 恢复已损生命 50% ｜ 起手霸体", "mech": "曲终恢复已损生命的 50%，进入 8 秒觉醒并解锁两式觉醒技；施展期间霸体，但并非无敌。", "lore": "她并非不知道红尘苦，只是不肯借忘字脱身。旧伤抚过一半便足够站稳，余下的一半留在弦里，替尚未讨回的债继续作声。"},
		{"name": "八音断识", "num": "八道音波 ｜ 本次 4／3／2／1… 伤 ｜ 每次觉醒一次", "mech": "觉醒中可用。同一目标本次受到 4／3／2／1 伤，此后均 1 伤；首次觉醒每道附 1 层六感尽失，后续每两道附 1 层。此状态在当前房间永久存在，目标使用非普通攻击的技能时受到等同层数的伤害。", "lore": "宫乐八音，金石丝竹匏土革木，原本各守其位。城破时礼乐尽毁，她偏要八音依次作响，叫仗技欺人者每动一次本领，都重新尝一遍失序的苦。"},
		{"name": "心魔引", "num": "基础 8 伤 ｜ 每层状态 +1 ｜ 转移自身减益", "mech": "觉醒中可用。引爆全房敌人的所有增益与减益，基础造成 8 伤、每层额外 +1；计时状态每 2 秒计 1 层并向上取整。随后将自身减益转移给所有存活目标，并净化自身。", "lore": "她见过太多人把罪推给时局，把苦留给别人。这一曲不许谁再装清白：藏在身上的恩怨全要当面算清，至于她自己的苦，也自有该领受的人。"},
	],
	"z003": [
		{"name": "崩云", "num": "4 伤 ｜ 前后重斩 ｜ 起手霸体 ｜ 斩影回响 2 伤", "mech": "以两种蓄力剑势之一横扫前后，造成 4 点伤害；蓄力期间霸体。落刀后，蓄力起点会留下一道刀痕并停留片刻，随后自行回响第二刀：刀痕内的敌人再受 2 点伤害并叠 1 层流血；回响命中时，本招冷却返还 1 秒。", "lore": "雪岭客栈掌柜让他扫门前雪，他嫌扫帚不够威风，偏要用剑。第一剑把雪掀回大堂，第二剑才劈出一条出路。掌柜扣了他三天饭钱，他却认定这招已经练成，还取了个响亮名字：崩云。"},
		{"name": "飞星送客", "num": "1 伤 ｜ 强力击退 ｜ 碰撞 1 伤", "mech": "近身冲拳造成 1 点伤害并轰退敌人；被击退者撞到同伴时双方各受 1 伤，撞墙时再受 1 伤。", "lore": "他做店小二时，最头疼喝多了不肯走的客人。一次被人揪住衣领，他顺手送出一拳，那人跌出门外，还撞翻了两个来接他的朋友。掌柜夸他送客周到，他便把这四个字当了真，日后谁要留下他，都先尝一遍这套礼数。"},
		{"name": "万籁停晷", "num": "全场时停 ｜ 杂兵 10 秒／精英 8 秒／首领 5 秒", "mech": "拍地停住当前场景所有敌人，不造成伤害；无视霸体并打断正在起手的招式，期间敌人不能行动。", "lore": "他替漏刻匠看摊，匠人说听完一壶水才准偷懒。听到第七日，他真能在两滴水之间出剑、收剑，再打个盹。后来掌落之时万籁俱寂，旁人只当时光停了，他却知道，不过是自己终于听清了那一滴水的空隙。"},
		{"name": "长夜明火", "num": "回血 2 ｜ 全部伤害 +2 ｜ 觉醒 8 秒", "mech": "起手霸体，立即恢复 2 点生命，并在 8 秒觉醒期间使全部伤害 +2，解锁两式觉醒技。", "lore": "他在荒寺借宿，半夜怕冷生火，差点烧了偏殿。老僧没罚他，只让他先煮一锅热汤赔罪。汤滚之后，满屋冻醒的人也都有了火气。此后他露宿再久，也不忘给自己留一团火：先暖过来，才有力气把仗打完。"},
		{"name": "舜华斩", "num": "8 伤 ｜ 路径贯穿 ｜ 2 层流血 ｜ 全程无敌", "mech": "觉醒中可用。向前突进并穿过敌身，对路径上的敌人造成 8 点伤害与 2 层流血，施展期间无敌。", "lore": "花朝会上，他替卖花姑娘挡下一个恶少，剑快得削断帽缨，却碰落了半架花。姑娘笑他只会煞风景，他便练到穿花而过、不碰一枝。后来舜华斩大成，花倒是留住了，那盆姑娘送的舜华却被他养死了。"},
		{"name": "天倾", "num": "全房 8 伤 ｜ 本房全部伤害 +3", "mech": "觉醒中可用。对全房敌人造成 8 点伤害；每个房间首次施展额外使本房全部伤害 +3，后续施展不再重复加持。", "lore": "雷雨天众人收摊，他偏爬上废塔，要看清一道雷究竟有多重。塔尖被劈没了，他抱着剑滚下来，头发竖了三日。再出剑时，天光仍从高处压落；至于他学到的道理，据说是「下次先躲，再谈天道」。"},
	],
}

## 化身固有被动，沿用被动解析面板展示。
const FORM_PASSIVES := {
	"c021": [
		{"name": "闪身", "desc": "闪避不受 0.5 秒最小间隔限制；完美闪避后，将该次攻击的伤害回敬给攻击者", "lore": "她演罗刹女时，最难的一折是贴着红绸旋身而不沾袖。火场里她以同样的步子穿过坠火，如今谁递来杀招，她便循旧拍把分量送回去。"},
		{"name": "红蝶", "desc": "每局首次死亡时满血复活，并将生命上限变为 100；此后每秒失去 1 点生命，仍可受伤，再次死亡按标准流程结算", "lore": "戏班旧俗，罗刹女谢幕时要放一只红纸蝶。她从火场回来后再没谢过幕，只把红绸系上双匕；那条借来的命，也就随着旧鼓点一点点烧下去。"},
	],
	"c013": [
		{"name": "圣僧", "desc": "免疫所有负面效果；单次受到的伤害最多为 3 点", "lore": "钟楼下听惯了求愿的话，他扫完地便去面壁，不让那些声音在心里过夜。所谓圣僧，不是没了凡心，只是不再让外物替自己起心动念。"},
		{"name": "降魔", "desc": "每实际造成 4 次伤害获得 1 层佛陀，跨房间保留，最多 3 层；每层使全部伤害 +1，已满 3 层时改为恢复 1 点生命。受到恰好 3 点伤害且会倒地的攻击时消耗 1 层，只免除倒地，不减免伤害", "lore": "钟楼下，他每敲满四记便停一息，听余音散尽再继续。面壁三年后，他把这份耐性带进了棒下：魔要一层层降，人也得一次次站稳。"},
	],
	"c023": [
		{"name": "墨梅", "desc": "每次实际造成伤害的攻击额外积累 1 墨锭，终局统一结算", "lore": "她在西岭用梅枝蘸墨，记下每年回雪压花的日子。后来枝成了软剑，账本却没丢：真正落在人身上的每一笔，留到终局再算。"},
		{"name": "霜梅", "desc": "基础生命为 60；每进入新房间恢复全部已损失生命，并按恢复量每 10 点向上取整，使本房间 K 尾鞭增加等量攻击；普攻不受 1 秒恢复限制", "lore": "西岭的回雪一来，折过的梅枝反倒能再立起来。她练剑也照这个脾气，每次重整衣襟，都把养回来的气力留给最后一鞭。"},
	],
	"z000": [
		{"name": "不朽", "desc": "生命恢复效果翻倍，额外生命最多为最大生命值的一半", "lore": "她守剑碑多年，见过山河换色，也见过旧伤愈合，出手却始终克制。所谓不朽，不是与谁争寿数，只是答应看守的事还没有做完。"},
		{"name": "剑宗", "desc": "伤害目标后，使其在当前房间的恢复效果永久减半", "lore": "她守剑碑时从不毁人兵器，只在来者剑脊上留一道细痕，提醒他胜负已分。后来这道分寸入了剑意：伤人可以不多，赖以回身的余地却要削去一半。"},
		{"name": "淑女", "desc": "每 20 秒恢复 10% 最大生命（受不朽双倍与额外生命联动），并获得 10 秒自信；期间释放技能的冷却减半，全部伤害 +1", "lore": "剑碑前无看客，她仍每次收剑都拂净袖口，不许胜负乱了礼数。下山后也是如此：越是久战，越要留十息从容，把下一剑递得清楚。"},
	],
	"z002": [
		{"name": "红 尘", "desc": "攻击她的敌人获得当前房间永久存在的怨；每累计 3 层怨，其每段伤害 -1，最低为 1", "lore": "旧都早成焦土，宫宴上的弦声却从未散去。每一记向她落下的兵刃，都会在新仇里添一笔旧怨。"},
		{"name": "红粉骷髅", "desc": "须臾：受到致命伤时，随机选择一名尚未替死过的癫狂目标，由其替承双倍溢出伤害，自身保留 1 生命", "lore": "红粉与骷髅不过一曲之隔。她把最后一根弦留给他人，让沉醉者替自己走到曲终。"},
		{"name": "神 伤", "desc": "每 30 秒对全房敌人造成 5 伤并附加 1 层心灵震撼；所有减益层数 +1，或计时 +5 秒，均尊重各自上限", "lore": "《黍离》再响时，故国便在每个人心里亡一次。曲声不止，伤痕也不会停在过去。"},
	],
	"z003": [
		{"name": "暗夜", "desc": "被命中后有 20% 概率不损失生命", "lore": "他行商时舍不得买火折子，赶夜路全凭耳朵。遇到剪径的，刀锋几次擦着衣角过去，他回来还先检查货少没少。走得多了，连黑里最难避的一击也能错开半寸；如今火折子攒了一匣，他仍舍不得点。"},
		{"name": "血色切割", "desc": "一局内，同类杂兵第 6 次、精英第 3 次、首领第 1 次被击败后，夺取其全部被动；化身的计数按首领计算", "lore": "他早年抓药落下个毛病，见什么都想配一服。别家的成名绝技在他眼里也是药材：见得够多，辨得够准，就能拿来治自己的剑。有人骂他偷师，他只回一句：药治百病，招治不服，各凭本事。"},
		{"name": "魅唤", "desc": "使用 P 时保留原招式效果，并从已夺取被动的实体中随机召唤 1 名协助者；同时最多存在 1 名，协助者数值不变，只攻击敌人，不追击也不误伤执卷者", "lore": "他记账从不用墨，谁欠他一场架，就在影子里留一道名字。缺钱时他翻酒账，缺帮手时也翻；被叫来的人多半不情愿，却又没法否认那一笔。至于招谁，全看他那天手指停在哪一页。"},
	],
}

## 化身通用动作：图鉴里也能点看待机 / 奔跑 / 闪避 / 滞空 / 受击 / 倒地
const ACT_ORDER := ["idle", "run", "dash", "air", "hurt", "dead"]
const ENEMY_ACT_ORDER := ["idle", "patrol", "chase", "hurt", "dead"]
const ACT_LABEL := {
	"idle": "待机", "patrol": "巡逻", "chase": "追击", "run": "奔跑",
	"dash": "闪避", "air": "滞空", "hurt": "受击", "dead": "倒地",
}

## 词条颜色只按统一分组决定；人物与释义数据由 StatusCodex 单独维护。
const TAG_GROUP_COLORS := {
	"战斗定位": "#e8dfc4",
	"招式机制": "#c89440",
	"来历与势力": "#5d8a93",
	"收录等阶": "#a8332a",
}

## 已正式定名的普通敌人招式资料；逻辑招式键与演示动画名可以不同。
const ENEMY_ATTACK_NAMES := {
	"c032": {"skill05-cankao": "坠锋", "skill01-cankao": "四响", "skill03-cankao": "旋征", "transform1": "神骸鸣钟"},
	"c008": {"skill04": "掷臂", "skill03": "崩坛", "skill02": "万佛手", "skill01": "佛眼"},
	"c009": {"skill03": "奋挥", "skill04": "墨颤", "skill05": "墨冲", "skill06": "断岳", "skill08": "陨构", "skill02-01": "贯昼"},
	"c015a1": {"skill01": "炎掌", "skill02": "愤炎碎", "skill3": "双拳", "skill05": "炎起"},
	"c001": {"skill01": "武撞"},
	"c016": {"skill01": "亡命三刀", "skill02": "螺旋鞭", "skill03": "升龙刀", "skill04": "双镰"},
	"c017": {"skill01": "开天", "skill02": "辟地", "skill03_2": "赶山三斧"},
	"c035": {"dart": "镖去", "sneak": "偷袭"},
	"c018": {"skill01": "镰舞", "skill02": "镰碎", "skill03": "镰意绽花"},
	"c012": {"skill01": "双剑斩", "skill02": "旋斩"},
	"c037": {"skill01": "亭台剑", "skill03": "转", "cangjian": "藏剑式", "jijian": "断楹祭剑"},
}
const ENEMY_ATTACK_MECH := {
	"c032": {
		"skill05-cankao": "普攻，无独立冷却；跃起以双斧劈落，造成 2 点伤害。实际造成伤害后获得「英勇」，下一招起手即消耗，整招每段伤害翻倍，落空也会消耗",
		"skill01-cankao": "冷却 24 秒；近身连续四击，分别造成 1／1／2／2 点伤害。首段实伤将目标固定在正前方并随鸣钟移动，直至收招；末段实伤附加 12 秒易伤，此后受到任意实伤固定 +1并刷新持续时间，易伤最多一层。无论是否命中，都会沿斧势位移并停在收招落点",
		"skill03-cankao": "冷却 36 秒；拉开距离后随机施展两种追击斧势。前劈造成 1 伤，旋转突进造成 2 伤，末尾下劈造成 3 伤并附加同一套易伤。旋转期间无敌、无实体且可穿过目标，整段只结算一次，按实际伤害恢复生命；被完美闪避则不伤害、不回血",
		"transform1": "生命低于 50%后立即优先觉醒（不再等攻击欲望），冷却 40 秒；蓄力期间无敌霸体，双斧完全展开时发动全场攻击，可被完美闪避。首次爆发造成 4 伤，同时恢复自身 25%生命并获得 10 点格挡；觉醒后仍可重复施展，继续恢复生命与格挡，攻击则按「神眷」结算",
	},
	"c008": {
		"skill04": "普攻，无独立冷却，由公共攻击欲望驱动；造成 3 点伤害，实伤附加 15 秒「剥离」，禁止目标全部被动",
		"skill03": "冷却 24 秒；先踢击造成 2 点伤害，再全身砸落造成 3 点伤害；仅砸落实伤附加 5 秒致残，封锁跳跃、闪避与带位移技能",
		"skill02": "冷却 30 秒；蓄力完成后，手掌戳落才连续结算五段伤害，每段造成 1 点伤害并附加 0.5 秒有效眩晕，同招后续段可穿过前段造成的受伤无敌",
		"skill01": "冷却 50 秒；扫描身前目标，必定命中且不被闪避、护盾或受伤无敌拦截。随机夺取其一个已拥有被动，双方分别失去与获得该被动，直至下一次扫描；下次先归还旧被动再重新夺取",
	},
	"c009": {
		"skill03": "普攻，无独立冷却；前两段各造成 1 点伤害，最后蓄力一击造成 3 点伤害",
		"skill04": "冷却 30 秒，开局前 5 秒禁用；机关举手时红点跟随目标，垂手后停止跟踪，落地时仍站在点内便被擒至操控者身前。先刺击造成 2 点伤害，后续滑斩把生命上限削至当前生命",
		"skill05": "冷却 35 秒，仅在拉开距离后释放；高速冲追，进入攻击范围立即造成 2 点伤害，此后每 0.5 秒再造成 2 点伤害直至冲刺结束，并触发拥有倒地动作的角色的倒地效果",
		"skill06": "冷却 25 秒；机关蓄力后向下砸地方才结算，造成 5 点伤害并附加 5 秒致残：封锁跳跃、Shift 闪避及所有带位移的技能",
		"skill08": "冷却 40 秒，远距离时按间距施展小跳或大跳；落地仍在范围内才造成 4 点伤害、远距击退与 5 秒致残",
		"skill02-01": "冷却 16 秒；短蓄力后向正前方发射贯穿整幅地图的激光，光束持续 0.8 秒、共结算两段，每段 2 点基础伤害。灼烧每累计 3 层使每段伤害 +1，最多 +3，6 秒未再命中则清零",
	},
	"c015a1": {
		"skill01": "无独立冷却；向身前劈掌，造成 2 点伤害",
		"skill02": "冷却 20 秒；连续捶地三次，分别造成 1／1／2 点伤害。每次实际命中附加并刷新 5 秒致残，封锁跳跃、Shift 闪避及所有带位移的技能",
		"skill3": "冷却 25 秒；向前锤出双拳，造成 3 点伤害与高额击退",
		"skill05": "炎骨觉醒后解锁，冷却 30 秒；抬腿时在执卷者脚下与两个随机位置显示预警，跺下时三处岩浆同时喷发。仍在岩浆区域内者受到 3 点伤害",
	},
	"c001": {
		"skill01": "场上没有其他敌人时向当前朝向冲锋，首次撞墙不损耐久，此后每次撞墙损失 1 点；接触执卷者便将其传送至武车 2 秒前的位置，无论是否受伤都会触发。实伤造成 2 点基础伤害并施加一层通缉，使召唤物实伤 +1，闪避武撞可解除通缉但不会阻止传送。掉头后逐个召唤敌人，每 4 个至少包含 1 个精英；耐久归零即战败",
	},
	"c016": {
		"skill01": "普攻，无独立冷却；前两刀只造成受击反馈，末刀造成 1 点伤害",
		"skill02": "中距离主动释放，冷却 9.6 秒；命中造成 1 点伤害",
		"skill03": "追击中瞬至身前，冷却 14.4 秒；出刀前有 0.87 秒蓄势，命中造成 2 点伤害并短暂击飞",
		"skill04": "近身技能，冷却 7.2 秒；命中造成 1 点伤害",
	},
	"c017": {
		"skill01": "普攻，无独立冷却；蓄势 0.64 秒后向上挥斧，造成 2 点伤害并短击退",
		"skill02": "近身技能，冷却 10.8 秒；1.58 秒后落斧造成 2 点伤害，命中后 8 秒无法跳跃",
		"skill03_2": "追击时释放，冷却 19.2 秒；行进间两劈各 1 伤，接原地大劈 2 伤，随后力竭 3 秒",
	},
	"c035": {
		"dart": "普攻，无独立冷却；连续两镖各造成 1 点伤害，同一次出手的第二镖可穿过首镖造成的受击无敌；整轮命中只附一组割伤，3 秒与 6 秒时各失去 1 点生命",
		"sneak": "追击时绕至目标身后，冷却 14.4 秒；蓄势 0.94 秒后砸击，造成 2 点基础伤害，可触发阴影",
	},
	"c018": {
		"skill01": "普攻，无独立冷却；0.30/0.60 秒两段各造成 2 点伤害；每段实际伤害附 1 层普通流血，每层每秒造成 1 伤，持续 3 秒，最多 5 层，新层刷新持续时间",
		"skill02": "近身重招，冷却 9.6 秒；0.73 秒后落镰造成 5 点伤害，并按目标实际失去的生命等量回复自身",
		"skill03": "近身技能，冷却 14.4 秒；0.83 秒后上挑，不造成直接伤害；命中将目标移至正上方并损失 2 点本局生命上限，跨房间保留；自身所有招式冷却永久缩短 50%，未命中或被防御时无效",
	},
	"c012": {
		"skill01": "普攻，无独立冷却；0.80/1.21 秒两段造成基础 1/2 点伤害，均计入当前剑意加成；首段实际命中后获得 1 层剑意，第二段附 1 层持续 3 秒的普通流血",
		"skill02": "冷却 12 秒；0.89 秒后腾空旋斩，造成基础 2 点伤害并计入当前剑意；实际命中后获得 1 层剑意，并令目标 8 秒无法使用 Shift 闪避，重复命中刷新持续时间",
	},
	"c037": {
		"skill01": "普攻，无独立冷却；三段伤害 1/1/2。第一剑蓄势约 0.98 秒，后两剑接连落下，挥剑与伤害保持同步",
		"skill03": "冷却 7.2 秒；造成 2 点伤害并击退。同一目标每次实际受创后，「转」对它的伤害永久 +1；不同目标分别计算",
		"cangjian": "冷却 9.6 秒；每次随机施展三种藏剑架势之一，三段伤害 1/2/3，末段附一组割伤，在 3 秒与 6 秒时各失去 1 点生命，多组独立计时",
		"jijian": "生命低于一半时自动触发，每场战斗仅一次；随机施展两种祭剑架势之一并回满生命。此后自身每段实际伤害都额外附一组独立割伤",
	},
}
const ENEMY_ATTACK_LORE := {
	"c032": {
		"skill05-cankao": "神军尚在时，她总第一个跃下城墙，双斧并拢，借全身下坠之势劈开攻城槌。如今城与军都没了，她仍从最高处落斧；斧刃咬中血肉的一瞬，旧日战意便会醒来，催她把下一招使得更重。",
		"skill01-cankao": "神骸钟铸成那日，铸钟师只敲了四下：一定骨，二正音，三开刃，四送神。她把四记锤法练成近身斧谱，首斧先将来客扣在钟前，余下三响再依次落下。最后一响不散，留在伤处，等人再碰时重新震开。",
		"skill03-cankao": "旧军被围时，她曾以双斧旋成钟轮，从敌阵这头一直转到那头。神骸钟以血续响，触刃者的一线精血便沿斧柄流回她身上；旋势将尽，她仍会补上当年的收军一劈，教让得不够快的人记住裂钟之声。",
		"transform1": "她平日只把双斧当兵器，直到半条命将尽，才解开腕上封链，让它们重新做回钟槌。长久蓄力是诸神沉默，双斧展开便是神骸钟再度轰鸣。遗骨中的余力随钟声归位，替她合拢伤口，也挡在下一击之前。",
	},
	"c008": {
		"skill04": "从前上门收账，最怕欠债人隔着人群装不熟。碎岳练出一手隔空递单的功夫：人站原地，双臂先越过人头把账单按到对方脸上。如今账单换成了封条，中者一切赊来的本事立即停用。",
		"skill03": "香账僧清账有两道手续：先踢开挡路的桌椅，再落印封存。碎岳嫌随身带印麻烦，便把自己当作那方大印，腾身连人砸下。印落，账定；至于被压在下面的桌椅还是人，他从不细看。",
		"skill02": "他清点功德钱从不用算盘，拇指掐数，其余四指轮落，五声脆响便报完一笔。后来桌案换成了来客的脑门，他仍要先屏息凝神，再利落敲足五下——账目可以喊冤，手指绝不乱数。",
		"skill01": "功德簿的夹页里藏着一面验货铜镜，不照皮相，专照一个人最倚仗的本领。碎岳每次开新账，都会先退回上一件抵押，再扣下眼前这件；他管这叫童叟无欺，至于物主答不答应，不在账内。",
	},
	"c009": {
		"skill03": "巨兽的前肢原是撑起墨堂门匾的梁柱。门匾早烂了，它仍保留当年扶正牌匾的三下动作：两下试正，最后一下总把东西按进墙里。",
		"skill04": "操控者修木偶时，会先用朱笔点住关节，再把散件拉回案前。如今朱点落在脚下，机爪认点不认人；那柄修边尖刀，也早从削竹改成了削命数。",
		"skill05": "这具巨兽曾替墨堂拖运雷车，最懂起步后不能回头。车早散架了，拉车的习性还在；它一旦压低肩颈，沿途无论石墩还是来客，都得让路。",
		"skill06": "断岳原是墨堂修山门用的打桩式。操控者把整具机关的重量压进一锤，专断落脚之根；他说山岳不能挪窝，便先教会挨锤的人也别乱动。",
		"skill08": "巨兽报废前最喜欢从屋脊跃回修理工坊，距离近便跨过一道沟，距离远便越过半座院。如今工坊成了战场，它仍把每一次落地当成归家，只是屋里的人承受不起。",
		"skill02-01": "墨霆怕雷，却亲手给巨兽装了引雷针。某夜雷火灌进机心，他情急下把余威压成一道细光；那线光曾照彻白昼，也把师徒二人最后一点清醒烧得越来越少。",
	},
	"c015a1": {
		"skill01": "鼎中第一味火从来不由薪柴生起，而是掌心血汗。巨汉炼鼎时总要先以掌试温；鼎毁以后，这一掌落下，旧火便顺着伤处留在了来客身上。",
		"skill02": "锁链拖住残鼎碎片，也拖住他的退路。他每逢怒极便连捶三次地面，前两下震碎立足，最后一下才把无处发泄的火全砸进去。",
		"skill3": "他曾以双拳合拢炉门，把将熄的火硬生生困回鼎中。如今炉门早不在了，两股劲风仍会把眼前人远远推出去，只留下掌风里的余焰。",
		"skill05": "残鼎碎片埋在他走过的土地下。抬腿时锁链牵动碎片示警，跺下时地底旧火重新找到出口，沿着三处裂口冲回人间。",
	},
	"c016": {
		"skill01": "他替商队挡过三次劫刀：第一刀断粮，第二刀断路，第三刀才明白命不是自己的。此后前两刀只逼破绽，最后一刀连旧账一起讨。",
		"skill02": "早年他在山口套惊马，绳索绕臂三周，借旋劲把畜生拉回。后来绳换成鞭，马没套住几匹，过路人倒是一个也没走远。",
		"skill03": "山民追崖羊练出一口憋气劲：先贴到猎物身前，再借上冲之势出刀。刀未必能升龙，人至少先离了泥地。",
		"skill04": "左手镰收麦，右手镰收债。丰年是农具，荒年就是兵器；他说两样都算收成，只看地里长的是谷子还是人。",
	},
	"c017": {
		"skill01": "族里老人说，天不是劈开的，是弯腰的人把它顶开的。他把这话记在斧上，先沉斧蓄足一身蛮劲，再向上还一记；天未必开得，挡路的人总得让开。",
		"skill02": "他少年时抡斧开山取石，一斧只能裂开薄薄一层。族人说地硬，他便练到斧落时连地底的根也震麻；中斧的人纵有轻功，也会一时忘了怎样跃起。",
		"skill03_2": "蛮人赶山，不靠快，靠不肯停。前两斧赶碎脚边的石头，最后一斧把余力全送进山里；斧落之后，他总得扶着膝盖喘口气，再拖着巨斧继续赶路。",
	},
	"c035": {
		"dart": "他小时候在镖局扫地，学不来趟子手的亮镖喝号，只会把断镖磨成薄片。第一记挑衣，第二记认肉；细伤像镖局的旧账，第三息记起，第六息再催，分文不少。",
		"sneak": "剃头匠的第一课不是动刀，而是绕到椅后，屏住呼吸，等客人垂下眼皮。他把剃刀换成短镖后仍守这条规矩：客人没有察觉，手艺才算做完。",
	},
	"c018": {
		"skill01": "旧时《夜巡》一折，他踩着两声梆子左旋右回，银镰先扫帷灯，再割流苏。如今没了锣鼓，他仍在心里数那两拍；镰刃滴下的血，恰好替他补上缺席的鼓点。",
		"skill02": "班主总嫌他压轴一跃不够沉，要他把整座戏台都震住。某夜台柱真被震断，他在尘埃里抱着双镰起身，才明白最能压住场子的不是唱腔。此后落镰仍照那一夜的力气，涌出的血则成了他站稳的台阶。",
		"skill03": "《血月绽花》的最后一势，原是用双镰托住扮花神的搭档，将她举过头顶。戏班散后，托举成了索命：旧寿数随花瓣折去，他则趁余音未断再舞一场。那一折始终没有谢幕，他也不愿再有。",
	},
	"c012": {
		"skill01": "听雨阁的剑仆替主人喂招，第一剑只许问招，不许取胜；等对方露出破绽，第二剑才准作答。他把双剑也取名为「问」与「答」——问剑留三分，答剑见血线，多年忍让不是不会赢，只是在等自己的那一剑。",
		"skill02": "旧时试剑，剑仆不得追出青石圆坪。他便练到跃起旋身，一剑同时截住坪中所有退路；如今圆坪早已不在，困住他的规矩却化作剑势，轮到对手在八息之内找不到闪避的落点。",
	},
	"c037": {
		"skill01": "青亭待客有三道礼：入门让半席，问剑让三分，临别送一程。他的第一剑替客掸尘，第二剑替客引路，第三剑才把不识趣的人送出门外。亭里的座位早已烂尽，他仍不肯省掉任何一道礼。",
		"skill03": "初执魔剑时，他每转一周便要削碎一套茶具，索性把桌椅全搬进亭外。后来亭空了，剑却越转越顺；同一个人若肯站在原地多看几转，他便会把对方当成旧客，一剑比一剑招待得隆重。",
		"cangjian": "三座旧亭各藏一种剑谱：临水亭藏刺，听雨亭藏撩，断山口那座藏回身。亭主只记得自己把剑藏好了，却忘了究竟藏在哪一座；于是每次出手，连他也要等剑现身才知今日行的是哪家的礼。",
		"jijian": "亭塌那夜，一根主楹先断。他上撩魔剑挑开坠瓦，再把剑插进亭心，以剑代柱撑起旧业。魔剑答应借他一条完整的命，代价是从此每笔人情都要由来客用割伤偿还。",
	},
}
const ENEMY_PASSIVES := {
	"c032": [
		{
			"name": "武神",
			"desc": "每次有效命中都令全部技能冷却 -3 秒，并获得 2 点格挡；格挡可无限叠加，受到伤害时先于生命扣除",
			"lore": "她不用回忆招式，身体比念头更早知道下一斧该落在哪里。每击中一次，旧军的攻防拍子便往前赶一拍，散在斧上的神骸余力也会凝成薄薄一层护光。",
		},
		{
			"name": "神眷",
			"desc": "首次觉醒后获得神圣庇佑：鸣钟的攻击不再扣除生命，每段有效命中累计 1 层圣光，英勇强化时改为 2 层；圣光本身不造成伤害，达到 36 层直接击败目标",
			"lore": "神骸钟重新响过以后，旧神终于认出了守钟人。自此她的斧刃不再索取血肉，只在来者身上记下圣痕；第三十六道圣痕亮起时，钟声替诸神宣读判决，而判决从不描述伤势，只写结局。",
		},
	],
	"c008": [
		{
			"name": "佛曰",
			"desc": "每次使用崩坛、万佛手或佛眼，获得一层金钟罩；每层可抵挡两次任意伤害，层数没有上限",
			"lore": "碎岳每动用一回真本事，便在金钟内页添一条新账，旁边照例批注「容辩两次」。所以每道金字都能替他硬吃两记。账页可以无限续，他也从没打算听到第三次申辩。",
		},
		{
			"name": "邪佛",
			"desc": "碎岳在场时，角色的自身增益无效，基础形态能力、回血与觉醒不受影响；局内强化、永久修炼与临时增益均被压制",
			"lore": "在他的账本上，外来的增益全算赊账，进门先冻结；自身本领、疗伤与临场觉醒则是现钱，不必封存。这不是宽厚，只是碎岳坚持收账也得照他的规矩——哪怕规矩本身最不讲理。",
		},
	],
	"c001": [
		{
			"name": "墨徒信仰",
			"desc": "武车没有生命值，只有耐久，普通攻击与持续伤害不能削减；首次撞墙免费，此后每次撞墙损失 1 点，归零即战败。所有召唤物的直接攻击比当前难度高一档，最高难度也继续提升",
			"lore": "车厢里的墨兵不记得旧主去了哪里，只记得武车仍在前行。他们把最后一点忠心系在车轴上，车每撞一次墙，便替它多担一分散架的苦。",
		},
		{
			"name": "璀璨时代",
			"desc": "武撞接触到执卷者时，无论是否造成实际伤害，都会将其传送至武车 2 秒前的位置；仅真实受伤时，接下来的本轮召唤总数 +1，精英名额按增加后的总数计算",
			"lore": "墨堂最盛时，武车驶过长街，人群总会退到它身后的灯火里。如今灯火早已熄灭，车轮却仍认那条旧路，要把挡在车前的人送回它已经驶过的时刻。",
		},
	],
	"c009": [
		{
			"name": "机关造物",
			"desc": "免疫流血、中毒等持续减益与普通控制；对满血角色造成的伤害翻倍；时间暂停是规则级能力，仍然生效",
			"lore": "巨兽没有血肉，操控者也早把自己的痛觉接进了机簧。针扎不进齿轮，喝令也叫不停发条；唯有让整段时光停下，这尊造物才会跟着歇一口气。",
		},
		{
			"name": "失心疯",
			"desc": "每次对执卷者造成真实伤害，自身生命上限 +1；受到任何伤害都会改为失去等量生命上限，因此生命始终等于上限",
			"lore": "雷火那晚，操控者把自己的心换成一枚会记仇的机心。每伤一人，机心便多刻一道槽；每受一伤，便连槽带肉一起削去。它从不缺损，也再不知道什么叫痊愈。",
		},
	],
	"c015a1": [
		{
			"name": "炎骨",
			"desc": "生命首次低于 50% 时永久觉醒并播放觉醒演出；此后受到的伤害减半并向上取整，解锁炎起。恢复生命不会撤销觉醒",
			"lore": "鼎裂那夜，碎片没有落地，而是烧进了他的骨头。只有真正伤及半条命，封在骨髓里的火才会醒来；一旦醒过，便再也不会睡回去。",
		},
		{
			"name": "炽热之心",
			"desc": "焚鼎造成的任何伤害都会附加 1 层怒焰。怒焰在焚鼎死亡前永久存在、层数无上限，共享计时每次固定造成 1 点真实伤害且不给予受伤无敌；1～8 层的间隔依次为 60／58／54／48／40／30／18／10 秒，8 层后固定 10 秒。每当怒焰实际造成一次伤害，恢复 10 点生命并刷新全部技能冷却，每次触发只结算一次",
			"lore": "他的心早已和残鼎同温。旁人的伤处每被旧火灼痛一次，那颗心便像重新添了炭，连疲惫的招式也跟着再度烧开。",
		},
	],
	"c037": {
		"name": "魔 爆",
		"desc": "死亡后会再次起身，魔化前扑并回斩，对前方大范围内的所有角色造成 3 点伤害。实际受创者仅在本房间受到魔诅：每个有冷却的技能使用后，其下一次冷却永久增加 1 秒",
		"lore": "青亭旧主以为是自己解封了魔剑，直到咽气后双手再次握剑，才知被解封的分明是剑中的魔。它借旧主的礼法站起，也借旧主的最后一次送客，把这座亭的规矩刻进每个人的招式里。",
	},
	"c016": {
		"name": "山 民",
		"desc": "每 5 秒恢复 1 点生命，不超过生命上限",
		"lore": "山里跌打损伤没人替你看，采苦草、嚼根茎，熬过几夜就算捡回来。他不懂医术，只知道山不会主动救谁，却总会给人留一口气。",
	},
	"c017": {
		"name": "蛮 力",
		"desc": "每段实际伤害都会短距离击退目标；全程霸体，普通控制与受击硬直无效，专门克制霸体的控制仍然有效",
		"lore": "他不信借力，也不懂收劲，只信斧头够沉、脊梁够直。山里倒下的树要靠自己扛回去，久了便养出一身不肯弯的蛮力；唯有真正压住他的规矩，才能让这把骨头低头。",
	},
	"c035": {
		"name": "阴 影",
		"desc": "从目标身后造成直接伤害时双倍暴击；割伤等持续伤害不触发此效果",
		"lore": "剃头铺的镜子照正面，椅后的影子只归他。多年替人修鬓，他知道后颈哪一寸最薄；离店后这份手艺没有浪费，只是不再收铜钱。",
	},
	"c018": {
		"name": "嗜 血",
		"desc": "生命低于 30% 时永久激活：每次有效命中回复 1 点生命，所有技能伤害 -1；虚弱时姿态与步伐改变并减速，回血后恢复动作与速度，但嗜血效果永不撤销",
		"lore": "他为演好将死的夜游神，曾三日不饮，把虚弱练得逼真。直到某次真伤了肺，台下彩声反而最盛。他便记住：越是站不稳，越要把最后一折唱完；只要尝见血，残烛也能烧到谢幕。",
	},
	"c012": {
		"name": "剑 意",
		"desc": "双剑斩首段或旋斩实伤获得 1 层剑意，最多 3 层；每层使后续每次命中伤害 +1，永不消耗。三层触发「剑意凝华」：生成唯一的同步分身，复制当前朝向与动作，后续同步出招并造成同等直伤、普通流血与封闪避；分身以约 60% 不透明的淡青水墨虚影和脚下淡青墨环区分，无敌、不可选中，不叠剑意、不再繁殖，本体死亡即消失",
		"lore": "阁中不许剑仆有自己的剑意，他便把每一次问答藏进斗笠下的朱绦。三层剑意圆满时，那个总被命令收剑的自己终于从雨里走出；朱丝如今系的是剑影，不再是他。",
	},
}

## 条目卡：化身 2 列 × 6 行；敌人按分类标题分组，以紧凑卡片容纳各组。
const CARD_X := 70.0
const CARD_Y := 136.0
const CARD_W := 190.0
const CARD_H := 62.0
const CARD_STEP_X := 200.0
const CARD_STEP_Y := 70.0
const CARD_COLS := 2
const CARD_MAX := 12
const ENEMY_GROUP_H := 24.0
const ENEMY_CARD_H := 44.0
const ENEMY_CARD_STEP_Y := 48.0

## 动画演示台：骨架站在台上，脚底贴台面下沿
const STAGE_X := 470.0
const STAGE_Y := 130.0
const STAGE_W := 380.0
const STAGE_H := 278.0
const SPRITE_X := 660.0
const SPRITE_Y := 406.0

## 技能解析面板（点击下方按钮后填充）
const DESC_X := 470.0
const DESC_Y := 414.0
const DESC_W := 380.0
const DESC_H := 132.0

## 右侧简介栏（名称 / 副标 / 词条 / 状态 / 可滚动背景故事）
const TEXT_X := 870.0
const TEXT_W := 340.0
const TITLE_Y := 122.0
const SUB_Y := 160.0
const TAG_Y := 184.0
const TAG_H := 52.0
const STAT_Y := 238.0
const LORE_Y := 264.0
const LORE_H := 322.0

## 动作按钮：8 列 × 最多 3 行（普攻 / 技能 / 通用动作 / 被动全塞得下）
const BTN_X := 470.0
const BTN_Y := 552.0
const BTN_W := 86.0
const BTN_H := 30.0
const BTN_GAP := 5.0
const BTN_COLS := 8
const BTN_STEP_Y := 34.0
const ACT_MAX := 24

## 解析面板顶部的操作提示：手机没有方向键，改成「再点一次」的说明
static func _hint_text() -> String:
	if OS.has_feature("mobile"):
		return "点击招式查看演示与机制；多变式再点一次切换"
	return "点击招式查看演示与机制；多变式用 ↑ / ↓ 切换"

## 人物背景故事（键 = 形态 / 敌人 id）
const LORE := {
	"c016": "山野间最常见的亡命刀客，一柄卷刃长刀便是全部家当。死后连名字都没人记得，只有崖边的乱刀还在等下一场雨。",
	"z002": "苏挽音曾是乱世宫中的琵琶乐师，最盛时一曲未终，殿外三军也会放轻脚步。城破那夜，帝王携金帛西逃，只命她留下奏曲安定人心。她便独坐空殿，把《黍离》从黄昏弹到天明，弦上不是亡国之音，是百姓最后一点不肯屈服的恨。宫门再开时，听曲的乱军已自相残杀，她却抱着琵琶走入人海，自此隐去乐师名姓，只称「绛弦」。她仍爱惜每一根弦，仍会在月下校音，只是再不为权贵献艺。有人说她以魔音摄心，她只答：心若无愧，何惧一曲故国。",
	"c017": "身高逾丈的蛮族力士，巨斧拖地，走一步便有石屑翻飞。他走得不快，却从不停在原地等人；一旦认准猎物，便拖着巨斧一步步赶上去。",
	"c035": "他曾是城门边的剃头匠，听遍过路人的秘密，却从不接话。后来有人花钱让他割掉一个叛徒的舌头，他收了钱，仍把那人的头发剃得很齐整。此后铺子没了，椅上多了另一种客人；他仍旧沉默，仍旧从椅后下刀。",
	"c018": "他曾是戏班里专演夜游神的双刀伶人，一双银镰在灯影里交错，像一轮不肯缺的月。班主说戏最要紧是懂得收，可他压轴的《血月绽花》从没等到谢幕——戏班欠下血债，那夜台下比台上先见了红。此后他仍按旧锣鼓点出手，只是再没人替他敲响收场那一声。",
	"c012": "他原是听雨阁替名家喂招的剑仆，只有斗笠，没有题名。阁主说剑意不可过三，免得仆比主先懂剑；阁毁那夜，他第一次使完第三层，雨里便站起另一个自己，替他斩断了那句「不许赢」。从此他带双剑远行，一名「问」，一名「答」——问尽来客，也终于开始回答自己。",
	"c037": "他原是渡头青亭的主人，青衣迎客，剑只用来裁茶、削笺、替迷路人斩开荆棘。墨堂来夺亭那夜，他拔出了亭基下祖辈封存的绿色魔剑；剑保住了亭，也顺着他的规矩一寸寸吃掉旧主。如今他仍守在原地，见客先施礼，三剑不差分毫，只在生命将尽时以剑代楹、向魔物再赊一命。来客若看见他死后重新站起，便会明白：青魇从来不是那柄剑的名字，而是亭主留在人间的最后一场噩梦。",
	"c009": "墨霆原是墨堂里最会修伞的机关师，怕雷，却偏给巨兽装了引雷针。一个雷夜过后，他和作品一起醒来：巨兽把他认作唯一会拧螺丝的人，他则再也想不起为什么要离开。如今他守在云坪，见客先看脚下——不是讲究礼数，只是在找下一颗能替换旧心的螺丝。",
	"c015a1": "紫焰锁链缠身的巨汉，曾以自身为鼎炼火，鼎裂后仍把余焰锁在骨里。他不再追逐无休止的厮杀，每次出手后便退开蓄势；可侵入对手体内的怒焰，会替他把这场战斗一直烧下去。",
	"c001": "双马拖曳的钢铁战车，车厢里封着仍在听令的墨兵。它不懂退让，只会撞向校场尽头，再掉头放出一轮新的追兵。",
	"c008": "碎岳原是悬空寺的香账僧，专管把香火钱与所求之事逐笔记清。日子久了，他发现功德簿上满是求寿、求财、求逢凶化吉，却没有一笔肯写自己该做什么。他索性把簿子改成借契：庇佑可以领，须拿最倚仗的本领作抵押。住持将他逐出山门，他反手把多年烂账捆在佛像背上拖走，半面山墙随之塌下，「碎岳」由此得名。如今他仍逢人先盘账：对方倒下，是抵押到期；自己倒下，便认作坏账核销。",
	"c032": "她曾是战神座前的女武神，也是神军溃败后唯一没有卸甲的人。诸神把战神遗骨铸成一口无舌之钟，命她永远镇守；她便拆下钟架上的两根骨槌，磨成双斧，从此既守钟，也替钟开口。年月太久，她已忘了自己的本名，只答「鸣钟」。她守的早不是神谕，而是钟里那一点不肯熄灭的旧主战意；若有来客能逼她解开腕上封链，便能听见神骸再次轰鸣，也能见识诸神如何越过血肉，直接给一个人写下结局。",
	"c021": "冷红绫原是临江戏班的舞姬，水袖一扬，满堂灯火都随她转身。班主讲她舞步太利，像袖里藏刀，她便索性将红绫裁短，换成两柄匕首。戏班失火那夜，她沿着唱熟的鼓点穿过浓烟，把最后一个孩子送出后门，自己却再没找到回去的路。此后她蒙面入行，只接那些无人敢接的活；价钱可以少谈，受邀看舞的人却一个也不能留。有人说她冷血，她从不辩。火场里喊哑的嗓子唱不得曲，唯有双匕仍记得旧拍：一进，一退，旋身时红裙如幕，落幕便见血。",
	"c013": "定山年少时在破庙挑水劈柴，最怕师父让他诵经，却最爱替山下农户赶野猪。寺里禅杖轻，他使着总像拈草，便捡矿场废铁打成狼牙棒，一棒下去，连庙门石阶也缺了半角。师父罚他面壁，他真在壁前站了三年，不是悔过，是在等心口那口恶气沉下去。后来山洪冲寺，他独自扛着断梁让香客先走，从此得了「定山」这个名号。如今他仍不擅讲慈悲，只把道理立在棒下：肯退一步的，留路；欺人太甚的，先问过他这一身不肯倒的骨头。",
	"c023": "白疏影生在西岭剑庐，幼时替人守炉，见的不是名剑出匣，而是钝铁回炉。她偏在废剑堆里捡出一柄软剑，缠上院中折梅，练出一身似鞭非鞭的路数。同门笑她剑不正，她便在下山那夜以一枝梅花连败七场，从此再没人问她师承。多年风雪早把青丝洗白，她仍穿旧黑袍，仍会在出手前拂去刃上的花瓣。只是梅香里藏着淬过的苦毒，沾身者初时不觉得疼，等察觉时，寒气已随血脉行远。她不争剑魁，也不收弟子，只在每年花信时回一次空山，把赢来的剑埋在老梅根下。",
	"z000": "洛惊鸿曾在天姥山守一座无人朝拜的剑碑，晨扫落叶，暮读残铭。师父只教她一个「听」字：听风擦过剑脊，听来客呼吸乱在何处，听完才准出剑。她用了十年，把满山松涛听成一部剑谱，下山时却连剑穗也未换新的。后来江湖盛传她一剑能惊飞鸿，真正见过的人却只记得她收剑很轻，像怕惊动檐下的雨。她不立门派，也不替谁正名，遇到欺人者便递上一句「请出剑」。若对方执意不退，她的下一剑总比话音先到；青衣掠过处，尘未扬，胜负已定。",
	"z003": "将去未还原是雪岭脚下的药商，后来卖过伞、说过书，也替人押过几趟不太平的镖。活计换得多，唯独嘴快、手快、学招快没改过。输给他的人常发现，自己最得意的一式会在他的影子里重演，像旧招不肯随主人散场，世人便称他「影殇」。他嫌这名字太丧气，仍忙着赶下一顿热饭、下一场热闹；只有月下拔剑时，满地影子比他人先安静。",
}

var _tab := TAB_STORY
var _sel := "" # 当前选中的条目 id
var _sfx: AudioStreamPlayer

var _preview = null # 演示台用的 SpineSprite
var _medal_fx: Node2D = null # 精英 / Boss 专属勋章演示
var _portrait: TextureRect = null
var _show_portrait := true # 有原画的条目默认展示原画；动作页保留完整 Spine 演示
var _pose_mixer = null
var _pending_anim := ""
var _idle_anim := "" # 待机动画名（默认演示 / 取消选中时回到这里）
var _current_anim := "" # 测试用：当前正在演的动作名
var _desc_rt: RichTextLabel # 技能解析面板
var _status_list: ScrollContainer = null
var _status_detail: RichTextLabel = null
var _status_buttons: Array = []
var _status_scroll := 0
var _story_list: ScrollContainer = null
var _story_detail: RichTextLabel = null
var _story_buttons: Array = []
var _story_scroll := 0

var _acts: Array = [] # 当前角色的动作条目（{label, anims, kind, src}）
var _act_btns: Array = [] # 动作按钮
var _act_bars: Array = [] # 选中条（按钮左缘朱砂细条）
var _act_labels: Array = [] # 按钮文字（亮底时转墨色）
var _hover_idx := -1 # 鼠标悬停的按钮下标（亮底 + 墨字）
var _pick_idx := -1 # 当前选中动作下标
var _pool: Array = [] # 当前动作的动画池
var _pool_i := 0 # 池内当前变式下标
var _music_on := true # 图鉴音乐开关：每次打开图鉴默认开启
var _music_btn: TextureButton = null # 音乐开关按钮：切开关只重绘它，不重建整个面板
var _build_gen := 0 # 构建代次：切页太快时，上一轮的延迟铺卡要自行作废


func _ready() -> void:
	layer = 9
	# 点击音常驻：切换条目 / 切页会整体重建界面，不能连它一起清掉
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_sfx.stream = SFX_CLICK
	_build()
	# 进入图鉴只留这一首：普通 BGM 由 play_solo 暂停并保留进度
	if _music_on:
		BGM.play_solo(CODEX_MUSIC)


func _exit_tree() -> void:
	# 离开图鉴恢复主菜单背景音乐（关闭音乐时这里是空操作）
	BGM.stop_solo()


func _build() -> void:
	_build_gen += 1
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	UiKit.fit_layer(self, [dim])

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1200, 640)
	win.position = Vector2(40, 40)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	_make_label("图  鉴", Vector2(70, 44), Vector2(320, 52), 40, PAPER)
	_music_btn = _make_button("音 乐 · " + ("开" if _music_on else "关"), Vector2(408, 52), Vector2(150, 44), 18, _toggle_music, _music_on)
	_make_button("故 事 集", Vector2(636, 52), Vector2(140, 44), 18, _switch_tab.bind(TAB_STORY), _tab == TAB_STORY)
	_make_button("敌 人", Vector2(788, 52), Vector2(140, 44), 18, _switch_tab.bind(TAB_ENEMY), _tab == TAB_ENEMY)
	_make_button("化 身", Vector2(940, 52), Vector2(140, 44), 18, _switch_tab.bind(TAB_FORM), _tab == TAB_FORM)
	_make_button("状 态", Vector2(1092, 52), Vector2(140, 44), 18, _switch_tab.bind(TAB_STATUS), _tab == TAB_STATUS)

	# 选中项失效（切页 / 刚收录）时退回第一条
	var entries := _entries()
	var ids: Array = []
	for e in entries:
		ids.append(str(e["id"]))
	if not ids.has(_sel):
		_sel = str(ids[0]) if not ids.is_empty() else ""

	if _tab == TAB_STATUS:
		var buff_count := 0
		var debuff_count := 0
		var tag_count := 0
		for e in entries:
			match str(e["kind"]):
				"buff":
					buff_count += 1
				"debuff":
					debuff_count += 1
				"tag":
					tag_count += 1
		_make_label("战斗状态 %d ｜ 增益 %d ｜ 减益 %d ｜ 人物词条 %d ｜ 全部开放" % [
			buff_count + debuff_count, buff_count, debuff_count, tag_count],
			Vector2(70, 104), Vector2(650, 26), 13, DIM)
		_build_status_detail()
		_build_status_list(entries)
	elif _tab == TAB_STORY:
		_make_label("四卷二十六章 ｜ 正史全部开放 ｜ 卷外手记%s" % ("已显影" if _developer_unlocked() else "未显影"),
			Vector2(70, 104), Vector2(650, 26), 13, DIM)
		_build_story_detail()
		_build_story_list(entries)
	else:
		var got := 0
		for e in entries:
			if not bool(e["locked"]):
				got += 1
		_make_label("%s %d / %d ｜ 点选招式查看解析" % ["已收录" if _tab == TAB_ENEMY else "已解锁", got, entries.size()],
			Vector2(70, 104), Vector2(470, 26), 13, DIM)

		# 先搭演示与详情，再铺条目卡：招式动画会甩出演示台，卡片后画才能盖住溢出的部分
		_build_detail()
		# 条目卡每张要两张贴图，数量又最多；推到下一帧再铺，避免和演示台挤在同一帧
		var gen := _build_gen
		await get_tree().process_frame
		if gen != _build_gen or not is_inside_tree():
			return

		if _tab == TAB_ENEMY:
			# 每个分组独占标题行；卡片只在组内按两列排布，行高不跨组累加。
			var y := CARD_Y
			for group in ["杂兵", "精英", "首领"]:
				var grouped: Array = []
				for e in entries.slice(0, CARD_MAX):
					if str(e["group"]) == group:
						grouped.append(e)
				if grouped.is_empty():
					continue
				_make_label("— %s —" % group, Vector2(CARD_X, y), Vector2(CARD_STEP_X + CARD_W, 20), 14, RED)
				y += ENEMY_GROUP_H
				for i in grouped.size():
					_make_card(grouped[i], i, y, true)
				var rows := int(ceil(float(grouped.size()) / CARD_COLS))
				y += rows * ENEMY_CARD_STEP_Y + 8.0
		else:
			for i in mini(entries.size(), CARD_MAX):
				_make_card(entries[i], i)

	_make_button("返  回", Vector2(70, 572), Vector2(130, 44), 20, _close, false, SFX_BACK)


## 重建：只留常驻节点（按钮不能在自身信号里销毁自己，故一律延迟调用）
func _refresh() -> void:
	if is_instance_valid(_status_list):
		_status_scroll = _status_list.scroll_vertical
	if is_instance_valid(_story_list):
		_story_scroll = _story_list.scroll_vertical
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_preview = null
	_medal_fx = null
	_portrait = null
	_pose_mixer = null
	_pending_anim = ""
	_desc_rt = null
	_status_list = null
	_status_detail = null
	_status_buttons = []
	_story_list = null
	_story_detail = null
	_story_buttons = []
	_current_anim = ""
	_acts = []
	_act_btns = []
	_act_bars = []
	_act_labels = []
	_hover_idx = -1
	_pick_idx = -1
	_pool = []
	_pool_i = 0
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_play_sfx(SFX_BACK)
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") and _pool.size() > 1:
		_cycle_pool(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and _pool.size() > 1:
		_cycle_pool(1)
		get_viewport().set_input_as_handled()


func _close() -> void:
	queue_free()


# ---------- 收录列表 ----------

## 当前页的条目：角色页使用统一卡片结构；状态与故事页保留完整静态资料。
func _entries() -> Array:
	if _tab == TAB_STATUS:
		return _status_catalog()
	if _tab == TAB_STORY:
		return _story_catalog()
	var out: Array = []
	if _tab == TAB_ENEMY:
		for kind in ["杂兵", "精英"]:
			for id in ENEMY_ORDER:
				if not EnemyTypes.TYPES.has(id):
					continue
				var t: Dictionary = EnemyTypes.get_type(id)
				if _enemy_kind(t, false) != kind:
					continue
				var n := Meta.enemy_kills(id)
				out.append({"id": id, "locked": n <= 0, "label": str(t["label"]), "group": kind,
					"sub": kind if n > 0 else "尚未收录"})
		for id in BossTypes.ROSTER:
			if not BossTypes.BOSSES.has(id):
				continue
			var b: Dictionary = BossTypes.get_boss(id)
			var nb := Meta.enemy_kills(id)
			var boss_kind := _enemy_kind(b, true)
			out.append({"id": id, "locked": nb <= 0, "label": str(b["label"]), "group": boss_kind,
				"sub": boss_kind if nb > 0 else "尚未收录"})
	elif _tab == TAB_FORM:
		for id in Skulls.ids():
			var p: Dictionary = Skulls.get_profile(id)
			var unlocked := Meta.is_unlocked(id)
			out.append({"id": id, "locked": not unlocked, "label": str(p["label"]),
				"sub": str(p.get("name", "")) if unlocked else "未解锁",
				"hero": bool(p.get("hero", false))})
	return out


func _status_catalog() -> Array:
	var out: Array = []
	for e in StatusCodex.entries() + StatusCodex.tag_entries():
		var item: Dictionary = e.duplicate()
		item["locked"] = false
		item["label"] = str(e["name"])
		item["sub"] = "%s · %s · %s" % [_status_kind_text(str(e["kind"])), str(e["group"]), _status_target_text(str(e["target"]))]
		out.append(item)
	return out


func _collection_progress() -> Dictionary:
	var progress := {"enemy": 0, "enemy_total": 0, "form": 0, "form_total": 0}
	for id in ENEMY_ORDER + BossTypes.ROSTER:
		progress["enemy_total"] += 1
		if Meta.enemy_kills(id) > 0:
			progress["enemy"] += 1
	for id in Skulls.ids():
		progress["form_total"] += 1
		if Meta.is_unlocked(id):
			progress["form"] += 1
	return progress


func _developer_unlocked() -> bool:
	var progress := _collection_progress()
	return progress["enemy"] == progress["enemy_total"] and progress["form"] == progress["form_total"]


func _story_catalog() -> Array:
	var out: Array = []
	for e in StoryCodex.entries():
		var item: Dictionary = e.duplicate()
		item["locked"] = false
		item["label"] = str(e["title"])
		item["sub"] = str(e["subtitle"])
		out.append(item)
	if _developer_unlocked():
		var developer: Dictionary = StoryCodex.developer_entry()
		developer["locked"] = false
		developer["label"] = str(developer["title"])
		developer["sub"] = str(developer["subtitle"])
		out.append(developer)
	else:
		var progress := _collection_progress()
		var progress_text := "敌人 %d/%d · 化身 %d/%d" % [
			progress["enemy"], progress["enemy_total"], progress["form"], progress["form_total"]]
		out.append({
			"id": "developer_afterword", "volume": "卷外 · 残页之外",
			"title": "卷外残页", "subtitle": progress_text, "summary": "",
			"sections": [], "cast": [], "relation_ids": [], "canon_refs": [],
			"locked": true, "label": "卷外残页", "sub": progress_text,
		})
	return out


func _enemy_kind(t: Dictionary, is_boss: bool) -> String:
	if is_boss:
		return "首领"
	return "精英" if bool(t.get("elite", false)) else "杂兵"


func _make_card(e: Dictionary, i: int, origin_y := CARD_Y, compact := false) -> void:
	var id := str(e["id"])
	var locked := bool(e["locked"])
	var card_h := ENEMY_CARD_H if compact else CARD_H
	var step_y := ENEMY_CARD_STEP_Y if compact else CARD_STEP_Y

	var card := TextureButton.new()
	card.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	card.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
	card.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	card.ignore_texture_size = true
	card.stretch_mode = TextureButton.STRETCH_SCALE
	card.size = Vector2(CARD_W, card_h)
	card.position = Vector2(CARD_X + (i % CARD_COLS) * CARD_STEP_X, origin_y + int(i / CARD_COLS) * step_y)
	if locked:
		card.modulate = Color(1, 1, 1, 0.55)
	card.pressed.connect(_select.bind(id))
	add_child(card)

	# 选中：卡片左缘一道朱砂细条，扫一眼就知道当前在看谁
	if id == _sel:
		var bar := ColorRect.new()
		bar.color = RED
		bar.size = Vector2(4, card_h)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bar)

	_entry_label(card, "？？？" if locked else str(e["label"]), 2 if compact else 8, 16 if compact else 18, PAPER)
	_entry_label(card, str(e["sub"]), 22 if compact else 34, 11 if compact else 12, DIM)

	# 英雄级主角（剑仙/绛弦/银夜）：卡片右上角一点金标，扫一眼就知道这是能觉醒的主角
	if not locked and bool(e.get("hero", false)):
		var tag := Label.new()
		tag.text = "英雄"
		tag.position = Vector2(CARD_W - 48, 6)
		tag.size = Vector2(40, 18)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.add_theme_color_override("font_color", GOLD)
		tag.add_theme_font_size_override("font_size", 12)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tag)


# ---------- 状态资料：全量静态目录，不进入角色模型与动作流程 ----------

func _status_kind_text(kind: String) -> String:
	match kind:
		"buff":
			return "增益"
		"debuff":
			return "减益"
		"tag":
			return "词条"
	return kind


func _status_target_text(target: String) -> String:
	match target:
		"player":
			return "执卷者"
		"enemy":
			return "敌人"
		"both":
			return "执卷者 / 敌人"
		"codex":
			return "敌人 / 化身"
	return target


func _build_status_list(entries: Array) -> void:
	_status_list = ScrollContainer.new()
	_status_list.name = "StatusList"
	_status_list.position = Vector2(60, CARD_Y)
	_status_list.size = Vector2(390, 426)
	_status_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_status_list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_status_list.add_theme_stylebox_override("panel", _panel_style())
	add_child(_status_list)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	_status_list.add_child(rows)

	var section := ""
	for e in entries:
		var id := str(e["id"])
		var section_key := "%s/%s" % [str(e["kind"]), str(e["group"])]
		if section_key != section:
			section = section_key
			var heading := Label.new()
			heading.text = "— %s · %s —" % [_status_kind_text(str(e["kind"])), str(e["group"])]
			heading.custom_minimum_size = Vector2(0, 27)
			heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			heading.add_theme_color_override("font_color", RED)
			heading.add_theme_font_size_override("font_size", 14)
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(heading)

		var button := TextureButton.new()
		button.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
		button.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
		button.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.custom_minimum_size = Vector2(348, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("status_id", id)
		button.pressed.connect(_select.bind(id))
		rows.add_child(button)
		_status_buttons.append(button)

		if id == _sel:
			var bar := ColorRect.new()
			bar.color = RED
			bar.size = Vector2(4, 54)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(bar)

		var title := Label.new()
		title.text = str(e["label"])
		title.position = Vector2(12, 4)
		title.size = Vector2(324, 25)
		title.add_theme_color_override("font_color", PAPER)
		title.add_theme_font_size_override("font_size", 16)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(title)

		var sub := Label.new()
		sub.text = str(e["sub"])
		sub.position = Vector2(12, 30)
		sub.size = Vector2(324, 19)
		sub.add_theme_color_override("font_color", DIM)
		sub.add_theme_font_size_override("font_size", 11)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(sub)

	_status_list.scroll_vertical = _status_scroll
	call_deferred("_restore_status_scroll")


func _restore_status_scroll() -> void:
	if is_instance_valid(_status_list):
		_status_list.scroll_vertical = _status_scroll


func _build_status_detail() -> void:
	var entry: Dictionary = {}
	for e in _status_catalog():
		if str(e["id"]) == _sel:
			entry = e
			break

	_status_detail = RichTextLabel.new()
	_status_detail.name = "StatusDetail"
	_status_detail.bbcode_enabled = true
	_status_detail.position = Vector2(470, 130)
	_status_detail.size = Vector2(740, 432)
	_status_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status_detail.scroll_active = true
	_status_detail.selection_enabled = true
	_status_detail.add_theme_stylebox_override("normal", _panel_style())
	_status_detail.add_theme_color_override("default_color", DIM)
	_status_detail.add_theme_font_size_override("normal_font_size", 16)
	_status_detail.add_theme_constant_override("line_separation", 4)
	_status_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_status_detail)
	if entry.is_empty():
		return

	var text := "[font_size=30][color=#f2e9d8]%s[/color][/font_size]\n" % str(entry["name"])
	text += "[color=#c89440]%s · %s · %s[/color]\n\n" % [
		_status_kind_text(str(entry["kind"])), str(entry["group"]), _status_target_text(str(entry["target"]))]
	text += "[font_size=18][color=#e8dfc4]%s[/color][/font_size]\n\n" % str(entry["summary"])
	var rules: Array = entry["rules"]
	if str(entry["kind"]) == "tag":
		text += "[font_size=18][color=#a8332a]词条释义 · 特征 / 规则 / 边界[/color][/font_size]\n"
		for i in rules.size():
			text += "\n%d. %s" % [i + 1, str(rules[i])]
		text += "\n\n[font_size=18][color=#a8332a]挂接角色[/color][/font_size]\n"
		var names: Array = []
		for member_id in entry.get("member_ids", []):
			names.append(StoryCodex.actor_name(str(member_id)))
		text += "\n" + "、".join(names)
		text += "\n\n[color=#8a857a]此页为特征摘要，逐条数值见招式与状态详情。[/color]"
		_status_detail.text = text
		return
	text += "[font_size=18][color=#a8332a]详细规则[/color][/font_size]\n"
	for i in rules.size():
		text += "\n%d. %s" % [i + 1, str(rules[i])]
	text += "\n\n[font_size=18][color=#a8332a]出处[/color][/font_size]\n"
	for source in entry["sources"]:
		text += "\n· %s" % str(source)
	text += "\n\n[color=#8a857a]状态条目无需解锁，随时可查。[/color]"
	_status_detail.text = text


# ---------- 故事集：静态编年目录，不进入角色模型与动作流程 ----------

func _build_story_list(entries: Array) -> void:
	_story_list = ScrollContainer.new()
	_story_list.name = "StoryList"
	_story_list.position = Vector2(60, CARD_Y)
	_story_list.size = Vector2(390, 426)
	_story_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_story_list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_story_list.add_theme_stylebox_override("panel", _panel_style())
	add_child(_story_list)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	_story_list.add_child(rows)

	var volume := ""
	for e in entries:
		var id := str(e["id"])
		if str(e["volume"]) != volume:
			volume = str(e["volume"])
			var heading := Label.new()
			heading.text = "— %s —" % volume
			heading.custom_minimum_size = Vector2(0, 30)
			heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			heading.add_theme_color_override("font_color", RED)
			heading.add_theme_font_size_override("font_size", 15)
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(heading)

		var button := TextureButton.new()
		button.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
		button.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
		button.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.custom_minimum_size = Vector2(348, 62)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bool(e["locked"]):
			button.modulate = Color(1, 1, 1, 0.55)
		button.set_meta("story_id", id)
		button.pressed.connect(_select.bind(id))
		rows.add_child(button)
		_story_buttons.append(button)

		if id == _sel:
			var bar := ColorRect.new()
			bar.color = RED
			bar.size = Vector2(4, 62)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(bar)

		var title := Label.new()
		title.text = str(e["label"])
		title.position = Vector2(12, 4)
		title.size = Vector2(324, 25)
		title.add_theme_color_override("font_color", PAPER)
		title.add_theme_font_size_override("font_size", 16)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(title)

		var sub := Label.new()
		sub.text = str(e["sub"])
		sub.position = Vector2(12, 33)
		sub.size = Vector2(324, 22)
		sub.add_theme_color_override("font_color", DIM)
		sub.add_theme_font_size_override("font_size", 11)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(sub)

	_story_list.scroll_vertical = _story_scroll
	call_deferred("_restore_story_scroll")


func _restore_story_scroll() -> void:
	if is_instance_valid(_story_list):
		_story_list.scroll_vertical = _story_scroll


func _build_story_detail() -> void:
	var entry: Dictionary = {}
	for e in _story_catalog():
		if str(e["id"]) == _sel:
			entry = e
			break

	_story_detail = RichTextLabel.new()
	_story_detail.name = "StoryDetail"
	_story_detail.bbcode_enabled = true
	_story_detail.position = Vector2(470, 130)
	_story_detail.size = Vector2(740, 432)
	_story_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_story_detail.scroll_active = true
	_story_detail.selection_enabled = true
	_story_detail.add_theme_stylebox_override("normal", _panel_style())
	_story_detail.add_theme_color_override("default_color", DIM)
	_story_detail.add_theme_font_size_override("normal_font_size", 16)
	_story_detail.add_theme_constant_override("line_separation", 5)
	_story_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_story_detail)
	if not entry.is_empty():
		_story_detail.text = _story_detail_text(entry)


func _story_detail_text(entry: Dictionary) -> String:
	var text := "[font_size=30][color=#f2e9d8]%s[/color][/font_size]\n" % str(entry["title"])
	text += "[color=#c89440]%s ｜ %s[/color]\n\n" % [str(entry["volume"]), str(entry["subtitle"])]
	if bool(entry.get("locked", false)):
		text += "[font_size=18][color=#e8dfc4]页缘还留着一处空白，要等所有同行者与敌手都在图鉴中显名。[/color][/font_size]\n"
		text += "\n[font_size=20][color=#a8332a]显影条件[/color][/font_size]\n"
		text += "\n收录全部普通敌人、精英与首领，并解锁全部六名化身。\n"
		text += "敌人须至少击败一次；化身须满足各自解锁条件或完成买断。两项进度须同时集齐。\n"
		text += "\n[color=#8a857a]这页卷外手记游离于残卷正史之外，只作纪念，不改变任何战斗或关卡规则。[/color]"
		return text
	text += "[font_size=18][color=#e8dfc4]%s[/color][/font_size]\n" % str(entry["summary"])
	for section in entry["sections"]:
		text += "\n[font_size=20][color=#a8332a]%s[/color][/font_size]\n" % str(section["title"])
		for paragraph in section["paragraphs"]:
			text += "\n%s\n" % str(paragraph)

	var cast: Array = entry["cast"]
	if not cast.is_empty():
		text += "\n[font_size=18][color=#a8332a]出场人物[/color][/font_size]\n"
		var names: Array = []
		for id in cast:
			names.append(_story_actor_name(str(id)))
		text += "、".join(names) + "\n"

	var chapter_relations: Array = []
	if str(entry["id"]) == "relation_overview":
		chapter_relations = StoryCodex.relations()
	else:
		for relation in StoryCodex.relations():
			if (entry["relation_ids"] as Array).has(str(relation["id"])):
				chapter_relations.append(relation)
	if not chapter_relations.is_empty():
		text += "\n[font_size=18][color=#a8332a]关联记载[/color][/font_size]\n"
		for relation in chapter_relations:
			text += "\n[color=#c89440]%s · %s ｜ %s · %s[/color]\n%s\n" % [
				_story_actor_name(str(relation["a"])), _story_actor_name(str(relation["b"])),
				str(relation["origin"]), str(relation["label"]), str(relation["text"])]
	if str(entry["id"]) == "developer_afterword":
		text += "\n[color=#8a857a]卷外手记保留现实开发者原文，不属于残卷正史，也不参与人物关系与共同年表。[/color]"
	else:
		text += "\n[color=#8a857a]故事集为公开残卷资料，不改变化身解锁与关卡流程。[/color]"
	return text


func _story_actor_name(id: String) -> String:
	return StoryCodex.actor_name(id)


# ---------- 右侧角色详情 ----------

func _build_detail() -> void:
	var m := _model(_sel)

	var stage := ColorRect.new()
	stage.color = Color(0, 0, 0, 0.28)
	stage.position = Vector2(STAGE_X, STAGE_Y)
	stage.size = Vector2(STAGE_W, STAGE_H)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	var portrait_path := str(m.get("portrait", ""))
	var has_portrait := not m.is_empty() and not bool(m["locked"]) and portrait_path != "" and ResourceLoader.exists(portrait_path)
	var showing_art := has_portrait and _show_portrait
	if has_portrait:
		_make_button("原 画", Vector2(688, 94), Vector2(78, 28), 13, _set_portrait_view.bind(true), _show_portrait)
		_make_button("动 作", Vector2(774, 94), Vector2(78, 28), 13, _set_portrait_view.bind(false), not _show_portrait)
	if not m.is_empty() and not bool(m["locked"]):
		_build_skin_switch()

	# 演示先画：甩出演示台的刀光会被后面的文字 / 卡片盖住，不会糊字
	var data = null
	if not m.is_empty() and not bool(m["locked"]):
		if showing_art:
			_make_portrait(portrait_path)
		else:
			data = load(str(m["data"]))
			if data == null or not data.call("is_skeleton_data_loaded"):
				data = null
			else:
				_make_preview(data, float(m["view_scale"]), str(m["idle"]))

	if _tab == TAB_ENEMY and not m.is_empty() and not bool(m["locked"]):
		var enemy_id := str(m["id"])
		var is_boss := BossTypes.ROSTER.has(enemy_id)
		var enemy_cfg: Dictionary = BossTypes.get_boss(enemy_id) if is_boss else EnemyTypes.get_type(enemy_id)
		if is_boss or bool(enemy_cfg.get("elite", false)):
			_medal_fx = SpineFX.spawn(self, "E21019", Vector2(STAGE_X + STAGE_W - 46, STAGE_Y + 54), {
				"anim": "boss" if is_boss else "elite", "height": 96.0, "center": true,
				"loop": true, "auto_free": false, "always": true, "z": 4,
			})
			if _medal_fx != null:
				_medal_fx.name = "CodexSpecialMedal"

	# 技能解析面板（点击动作按钮后填充）
	_desc_rt = RichTextLabel.new()
	_desc_rt.bbcode_enabled = true
	_desc_rt.position = Vector2(DESC_X, DESC_Y)
	_desc_rt.size = Vector2(DESC_W, DESC_H)
	_desc_rt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_desc_rt.scroll_active = true
	_desc_rt.add_theme_stylebox_override("normal", _panel_style())
	_desc_rt.add_theme_color_override("default_color", DIM)
	_desc_rt.add_theme_font_size_override("normal_font_size", 13)
	_desc_rt.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_desc_rt)
	_desc_rt.text = "[color=#8a857a]%s[/color]" % _hint_text()

	if m.is_empty():
		return

	_make_label(str(m["title"]), Vector2(TEXT_X, TITLE_Y), Vector2(TEXT_W, 34), 26, PAPER)
	_make_label(str(m["sub"]), Vector2(TEXT_X, SUB_Y), Vector2(TEXT_W, 22), 13, DIM)

	# 词条：按组配色（战斗定位纸白 / 机制赭金 / 出身石青 / 稀有度朱砂）
	var tags: Array = m["tags"]
	var tag_rt := RichTextLabel.new()
	tag_rt.bbcode_enabled = true
	tag_rt.position = Vector2(TEXT_X, TAG_Y)
	tag_rt.size = Vector2(TEXT_W, TAG_H)
	tag_rt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tag_rt.scroll_active = false
	tag_rt.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tag_rt.add_theme_font_size_override("normal_font_size", 13)
	tag_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tags.is_empty():
		tag_rt.text = "[color=#8a857a]词条未解锁[/color]"
	else:
		var parts: Array = []
		for t in tags:
			var nm := str(t)
			parts.append("[color=%s]· %s[/color]" % [str(TAG_GROUP_COLORS.get(StatusCodex.tag_group(nm), "#e8dfc4")), nm])
		tag_rt.text = "  ".join(parts)
	add_child(tag_rt)

	if str(m["stat"]) != "":
		_make_label(str(m["stat"]), Vector2(TEXT_X, STAT_Y), Vector2(TEXT_W, 24), 13,
			RED if _tab == TAB_ENEMY else GOLD)

	# 背景故事：中文没有词边界，用 RichTextLabel 按矩形宽度逐字换行；过长可在栏内上下滚动
	var lore := RichTextLabel.new()
	lore.text = str(m["lore"])
	lore.position = Vector2(TEXT_X, LORE_Y)
	lore.size = Vector2(TEXT_W, LORE_H)
	lore.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	lore.scroll_active = true
	lore.add_theme_stylebox_override("normal", StyleBoxEmpty.new()) # 去掉默认内边距，和上方标题左对齐
	lore.add_theme_color_override("default_color", RED if bool(m["locked"]) else DIM)
	lore.add_theme_font_size_override("normal_font_size", 15)
	lore.mouse_filter = Control.MOUSE_FILTER_STOP # 鼠标在简介区才滚得动
	add_child(lore)

	if bool(m["locked"]):
		_make_label("尚 未 收 录", Vector2(STAGE_X, STAGE_Y + 108), Vector2(STAGE_W, 40), 24, RED)
		_desc_rt.text = "[color=#8a857a]%s[/color]" % str(m["lore"])
		return

	if showing_art:
		_desc_rt.text = "[color=#8a857a]完整角色原画。点击上方「动作」可查看待机、招式与机制解析。[/color]"
		return

	if data == null:
		_desc_rt.text = "[color=#8a857a]演示暂时不可用，仍可查看文字资料。[/color]"
		return

	# 动作按钮：先按骨架里真实存在的动画过滤，再铺 8 列网格
	var anims := _anim_names(data)
	var built: Array = []
	for a in m["actions"]:
		if _trim_anims(a, anims):
			built.append(a)
	if built.size() > ACT_MAX:
		built = built.slice(0, ACT_MAX)
	_acts = built
	for i in _acts.size():
		_make_action_button(_acts[i], i)


## 外观切换：只列出已购皮肤，购自墨锭商栈；未购买的按原装展示
func _build_skin_switch() -> void:
	var is_enemy := _tab == TAB_ENEMY
	var defs: Array = Skins.defs(_sel, is_enemy)
	if defs.is_empty():
		return
	var opts := _skin_options(_sel, is_enemy)
	if opts.size() <= 1:
		return
	var worn := Skins.worn(_sel)
	var idx := 0
	for i in opts.size():
		if str(opts[i]["id"]) == worn:
			idx = i
	_make_button("‹", Vector2(470, 94), Vector2(28, 28), 16, _cycle_skin.bind(-1))
	_make_button(str(opts[idx].get("name", "原装")), Vector2(502, 94), Vector2(142, 28), 13,
		_cycle_skin.bind(1), worn != "")
	_make_button("›", Vector2(648, 94), Vector2(28, 28), 16, _cycle_skin.bind(1))


func _skin_options(owner_id: String, is_enemy: bool) -> Array:
	var out: Array = [{"id": "", "name": "原装"}]
	for d in Skins.defs(owner_id, is_enemy):
		if Skins.owned(owner_id, str(d["id"])):
			out.append(d)
	return out


func _cycle_skin(step: int) -> void:
	var is_enemy := _tab == TAB_ENEMY
	var opts := _skin_options(_sel, is_enemy)
	if opts.size() <= 1:
		return
	var worn := Skins.worn(_sel)
	var idx := 0
	for i in opts.size():
		if str(opts[i]["id"]) == worn:
			idx = i
	idx = posmod(idx + step, opts.size())
	Skins.wear(_sel, str(opts[idx]["id"]))
	call_deferred("_refresh")


## 条目详情模型：敌人与化身统一成同一份结构，右栏只认这一份
func _model(id: String) -> Dictionary:
	if id == "":
		return {}
	if _tab == TAB_ENEMY:
		var is_boss := BossTypes.ROSTER.has(id)
		var t: Dictionary = BossTypes.get_boss(id) if is_boss else EnemyTypes.get_type(id)
		var times := Meta.enemy_kills(id)
		if times <= 0:
			return {"id": id, "locked": true, "title": "？？？", "sub": "尚未收录", "stat": "",
				"tags": [], "data": str(t["data"]),
				"lore": "还没有击败过这只敌人。\n在战斗中击杀它之后，这里会亮出它的来历、招式与数值。",
				"view_scale": 1.0, "idle": "stand", "actions": []}
		return {
			"id": id, "locked": false, "title": str(t["label"]),
			"sub": "%s · 生命 %d" % [_enemy_kind(t, is_boss), int(t.get("hp", 0))],
			"stat": "已击败 %d 次" % times,
			"tags": StatusCodex.tags_for(id),
			"lore": str(LORE.get(id, "")),
			"data": str(t["data"]),
			"portrait": str(t.get("portrait", "")),
			"view_scale": _enemy_scale(t, is_boss),
			"idle": str(t["anim"]["idle"]),
			"actions": _enemy_actions(t, is_boss, id),
		}

	var p: Dictionary = Skulls.get_profile(id)
	if not Meta.is_unlocked(id):
		return {"id": id, "locked": true, "title": "？？？", "sub": Meta.unlock_hint(id), "stat": "",
			"tags": [], "data": str(p["data"]),
			"lore": "尚未解锁的化身。\n" + Meta.unlock_hint(id) + "（" + Meta.unlock_progress(id) + "）",
			"view_scale": 1.0, "idle": "stand", "actions": []}
	return {
		"id": id, "locked": false, "title": str(p["label"]),
		"sub": "化身 · %s" % str(p.get("name", "")),
		"stat": "契合 " + Meta.mastery_text(id),
		"tags": StatusCodex.tags_for(id),
		"lore": str(LORE.get(id, "")),
		"data": str(p["data"]),
		"portrait": str(p.get("portrait", "")),
		"view_scale": float(p["scale"]) * 1.45, # 游戏内 128px 高，图鉴里放大到约 186px
		"idle": str(p["anim"]["idle"]),
		"actions": _form_actions(p, id),
	}


## 预览缩放：杂兵 / 精英 / Boss 各给一档放大倍率，别让巨物溢出演示台
func _enemy_scale(t: Dictionary, is_boss: bool) -> float:
	var base := float(t["scale"])
	if is_boss:
		# 人形 Boss 可用独立预览倍率；巨型 Boss 仍缩到约 225px，避免溢出演示台。
		return float(t.get("codex_scale", base * 0.5))
	if bool(t.get("elite", false)):
		return base * 1.25
	return base * 1.55


# ---------- 动作清单 ----------

## 动作条目统一结构：{label, anims(动画池), kind(attack/skill/act/passive/enemy_atk/transform), src}
## anims 只放一条 = 单变式；放多条 = 点开后用 ↑ / ↓ 手动切换；sequence 只用于顺序连段，不当变式
func _form_actions(p: Dictionary, form_id: String) -> Array:
	var out: Array = []
	var atks: Array = p.get("attacks", [])
	var attack_text: Array = FORM_ATTACK_TEXT.get(form_id, [])
	for i in atks.size():
		var a: Dictionary = atks[i]
		var action := {"label": "无名式", "anims": _anims_of(a), "kind": "attack", "src": a}
		if i < attack_text.size():
			var text: Dictionary = attack_text[i]
			action["label"] = str(text["name"])
			action["num"] = str(text["num"])
			action["mech"] = str(text["mech"])
			action["lore"] = str(text["lore"])
		out.append(action)
	var keys: Array = p.get("hud_skills", [])
	var skills: Dictionary = p.get("skills", {})
	var skill_text: Array = FORM_SKILL_TEXT.get(form_id, [])
	for i in keys.size():
		var key := str(keys[i])
		if not skills.has(key):
			continue
		var cfg: Dictionary = skills[key]
		var pool: Array = cfg.get("pool", [key])
		var action := {
			"label": "无名式",
			"anims": (pool as Array).duplicate(),
			"kind": "skill", "src": cfg,
		}
		if i < skill_text.size():
			var text: Dictionary = skill_text[i]
			action["label"] = str(text["name"])
			action["num"] = str(text["num"])
			action["mech"] = str(text["mech"])
			action["lore"] = str(text["lore"])
		out.append(action)
	var map: Dictionary = p.get("anim", {})
	for act in ACT_ORDER:
		if map.has(act):
			out.append({"label": str(ACT_LABEL.get(act, act)), "anims": [str(map[act])], "kind": "act", "src": {}})
	for passive in FORM_PASSIVES.get(form_id, []):
		out.append({"label": str(passive["name"]), "anims": [], "kind": "passive", "src": {"id": form_id, "passive": passive}})
	return out


func _enemy_actions(t: Dictionary, is_boss: bool, id: String) -> Array:
	var out: Array = []
	var names: Array = []
	if is_boss:
		for st in t.get("stages", []):
			for n in st.get("attacks", []):
				if not names.has(str(n)):
					names.append(str(n))
	else:
		for n in t.get("attacks", []):
			names.append(str(n))

	var chains: Dictionary = t.get("attack_chain", {})
	var chained: Array = []
	for start in chains:
		var next_anim := str((chains[start] as Dictionary).get("anim", ""))
		if not next_anim.is_empty():
			chained.append(next_anim)

	for i in names.size():
		var n := str(names[i])
		if chained.has(n):
			continue # 连段收尾不是独立招式，不额外生成第四个按钮
		var attack_names: Dictionary = ENEMY_ATTACK_NAMES.get(id, {})
		var visual := str((t.get("move_anims", {}) as Dictionary).get(n, n))
		var visuals: Array = (t.get("move_pool", {}) as Dictionary).get(n, [visual])
		var action := {"label": str(attack_names.get(n, "招式 %d" % (i + 1))), "anims": visuals, "key": n, "kind": "enemy_atk", "src": t, "id": id}
		if chains.has(n):
			var next_anim := str((chains[n] as Dictionary).get("anim", ""))
			if not next_anim.is_empty():
				action["sequence"] = [n, next_anim]
		out.append(action)

	var limit: Dictionary = t.get("limit", {})
	if not limit.is_empty():
		var key := str(limit.get("move", "jijian"))
		var attack_names: Dictionary = ENEMY_ATTACK_NAMES.get(id, {})
		out.append({"label": str(attack_names.get(key, "限定技")), "anims": (limit.get("pool", []) as Array).duplicate(),
			"key": key, "kind": "enemy_atk", "src": t, "id": id})

	var map: Dictionary = t.get("anim", {})
	for act in ENEMY_ACT_ORDER:
		if is_boss and act == "patrol":
			continue # 所有 Boss 均无巡逻，只保留实际追击动作。
		if map.has(act):
			out.append({"label": str(ACT_LABEL.get(act, act)), "anims": [str(map[act])], "kind": "act", "src": {}})

	if is_boss:
		for st in t.get("stages", []):
			var tf := str(st.get("transform", ""))
			if tf != "":
				out.append({"label": "变身", "anims": [tf], "kind": "transform", "src": st})
				break
	var passive_entry = ENEMY_PASSIVES.get(id, {})
	var passives: Array = passive_entry if typeof(passive_entry) == TYPE_ARRAY else [passive_entry]
	var burst: Dictionary = t.get("death_burst", {})
	var passive_anims: Array = [str(burst.get("anim", "transform"))] if not burst.is_empty() else []
	for passive in passives:
		if (passive as Dictionary).is_empty():
			continue
		var passive_action := {"label": str(passive.get("name", "被 动")), "anims": passive_anims, "kind": "passive", "src": {"id": id, "passive": passive}}
		if not burst.is_empty():
			passive_action["death_finisher"] = true
		out.append(passive_action)
	return out


func _anims_of(a: Dictionary) -> Array:
	if a.has("pool"):
		var pool: Array = a["pool"]
		if not pool.is_empty():
			return (pool as Array).duplicate()
	if a.has("anim"):
		return [str(a["anim"])]
	return []


## 过滤骨架里不存在的动画（变式池里缺的单独剔掉，不影响整条技能）
func _trim_anims(a: Dictionary, anims: Dictionary) -> bool:
	if str(a["kind"]) == "passive":
		return true
	var keep: Array = []
	for nm in a["anims"]:
		if anims.has(str(nm)):
			keep.append(str(nm))
	if keep.is_empty():
		return false
	a["anims"] = keep
	return true


## 普攻数值：只展示玩家需要的伤害与效果，不暴露内部射程参数。
func _attack_num(a: Dictionary, _anim: String) -> String:
	var dmg := int(a.get("damage", 1))
	if a.has("hits"):
		var hits: Array = a["hits"]
		if not hits.is_empty() and typeof(hits[0]) == TYPE_DICTIONARY:
			var h: Dictionary = hits[0]
			dmg = int(h.get("damage", dmg))
	var parts: Array = ["%d 伤" % dmg]
	if a.has("projectile"):
		parts.append("远程")
	if a.has("launch"):
		parts.append("击飞")
	return " ｜ ".join(parts)


func _attack_desc(a: Dictionary) -> String:
	if a.has("launch"):
		return "把敌人挑到空中，落地硬直"
	if a.has("projectile"):
		return "挥剑甩出剑气，远程命中"
	if a.has("both"):
		return "回身横扫，身前身后都能命中"
	return "近身连击"


## 技能数值：伤害 / 治疗 / 强化 / 时停 / 远程（冷却单列一行）
func _skill_num(cfg: Dictionary) -> String:
	var parts: Array = []
	if cfg.has("heal"):
		parts.append("回血 %d" % int(cfg["heal"]))
	if cfg.has("buff_damage"):
		parts.append("加伤 +%d / %ds" % [int(cfg["buff_damage"]), int(cfg.get("buff_time", 0))])
	if cfg.has("tick"):
		var tick: Dictionary = cfg["tick"]
		parts.append("转击 %d 伤 / %.2fs" % [int(tick.get("damage", 1)), float(tick.get("interval", 0.5))])
	var dmg := 0
	var cnt := 0
	for h in cfg.get("hits", []):
		if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has("damage"):
			dmg = maxi(dmg, int((h as Dictionary)["damage"]))
			cnt += 1
	if dmg == 0 and cfg.has("damage"):
		dmg = int(cfg["damage"]) # 单段技能（hit_at 按动画查表）的伤害写在 cfg 顶层
	if dmg > 0:
		parts.append("%d 伤%s" % [dmg, (" ×%d" % cnt) if cnt > 1 else ""])
	if cfg.has("stop"):
		parts.append("时停")
	for h in cfg.get("hits", []):
		if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has("projectile"):
			parts.append("远程")
			break
	if cfg.has("projectile"):
		parts.append("远程")
	if cfg.has("awaken_time"):
		parts.append("觉醒 %ds" % int(cfg["awaken_time"]))
	return " ｜ ".join(parts)


## 技能机制标签：从配置里能读出来的机制逐条拍上去（真正的文字说明之后由 LORE/文案补）
func _skill_desc(cfg: Dictionary) -> String:
	var tags: Array = []
	if bool(cfg.get("poise", false)):
		tags.append("起手霸体")
	if bool(cfg.get("invincible", false)):
		tags.append("全程无敌")
	if bool(cfg.get("reflect", false)):
		tags.append("挨打反伤")
	if bool(cfg.get("ranged_guard", false)):
		tags.append("弹反远程")
	if bool(cfg.get("path", false)):
		tags.append("路径贯穿")
	if cfg.has("blink_from"):
		tags.append("瞬步位移")
	if cfg.has("knockback"):
		tags.append("击退撞墙")
	if bool(cfg.get("require_buff", false)):
		tags.append("觉醒限定")
	if bool(cfg.get("full_screen", false)):
		tags.append("全屏伤害")
	if cfg.has("room_buff"):
		tags.append("每房一次强化")
	# 命中追加效果：叠流血 / 命中定身 / 命中晕眩 / 命中中毒 / 自身金钟罩
	var bleed := false
	var root := false
	var stun := false
	var poison := false
	var shield := false
	for h in cfg.get("hits", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if int((h as Dictionary).get("bleed", 0)) > 0:
			bleed = true
		if float((h as Dictionary).get("stun", 0.0)) > 0.0:
			stun = true
		if float((h as Dictionary).get("poison", 0.0)) > 0.0:
			poison = true
		if (h as Dictionary).has("self_shield"):
			shield = true
		var proj = (h as Dictionary).get("projectile", null)
		if typeof(proj) == TYPE_DICTIONARY and float((proj as Dictionary).get("root", 0.0)) > 0.0:
			root = true
		if float((h as Dictionary).get("root", 0.0)) > 0.0:
			root = true
	if int(cfg.get("bleed", 0)) > 0:
		bleed = true # 池技能（hit_at 按动画查表）的 bleed 写在 cfg 顶层
	if bleed:
		tags.append("命中叠流血")
	if root:
		tags.append("命中定身")
	if stun:
		tags.append("命中晕眩")
	if poison:
		tags.append("命中中毒")
	if shield:
		tags.append("自身金钟罩")
	return " · ".join(tags)


## 敌人招式数值：只展示段数、伤害与恢复时间；判定时刻和射程留在配置内。
func _enemy_num(t: Dictionary, anim: String, sequence: Array = [], id: String = "") -> String:
	if id == "c009":
		match anim:
			"skill04":
				return "刺击 2 伤 ｜ 滑斩削至当前命限"
			"skill05":
				return "每 0.5 秒 2 伤 ｜ 倒地"
			"skill02-01":
				return "每 0.5 秒 1 伤 ｜ 灼烧递增"
	var parts: Array = []
	var hit_at: Dictionary = t.get("hit_at", {})
	var damage: Dictionary = t.get("damage", {})
	if sequence.size() > 1:
		var first := str(sequence[0])
		var last := str(sequence[sequence.size() - 1])
		var hs = hit_at.get(first, [])
		var hit_count := (hs as Array).size() if typeof(hs) == TYPE_ARRAY else 1
		parts.append("连劈 %d 段 ｜ 各 %d 伤" % [hit_count, int(damage.get(first, 1))])
		parts.append("大劈 %d 伤" % int(damage.get(last, 1)))
		var chain: Dictionary = (t.get("attack_chain", {}) as Dictionary).get(first, {})
		var recovery := float(chain.get("recovery", 0.0))
		if recovery > 0.0:
			parts.append("力竭 %.0f 秒" % recovery)
		return " ｜ ".join(parts)
	if hit_at.has(anim):
		var h = hit_at[anim]
		if typeof(h) == TYPE_ARRAY:
			parts.append("%d 段" % (h as Array).size())
	var d = damage.get(anim, 1)
	if typeof(d) == TYPE_ARRAY:
		var damage_text: Array = []
		for value in d:
			damage_text.append(str(int(value)))
		parts.append("/".join(damage_text) + " 伤")
	else:
		parts.append("%d 伤" % int(d))
	return " ｜ ".join(parts)


func _num_for(a: Dictionary, anim: String) -> String:
	if a.has("num"):
		return str(a["num"])
	match str(a["kind"]):
		"attack":
			return _attack_num(a["src"], anim)
		"skill":
			return _skill_num(a["src"])
		"enemy_atk":
			return _enemy_num(a["src"], str(a.get("key", anim)), a.get("sequence", []), str(a.get("id", "")))
	return ""


func _mech_for(a: Dictionary) -> String:
	if a.has("mech"):
		return str(a["mech"])
	match str(a["kind"]):
		"attack":
			return _attack_desc(a["src"])
		"skill":
			return _skill_desc(a["src"])
		"enemy_atk":
			var key := str(a.get("key", str((a["anims"] as Array)[0])))
			return str((ENEMY_ATTACK_MECH.get(str(a.get("id", "")), {}) as Dictionary).get(key, ""))
		"transform":
			return "生命降低后改变战斗姿态"
	return ""


func _cd_for(a: Dictionary) -> float:
	if str(a["kind"]) == "skill":
		return float((a["src"] as Dictionary).get("cooldown", 0.0))
	if str(a["kind"]) == "enemy_atk":
		var key := str(a.get("key", str((a["anims"] as Array)[0])))
		var rules: Dictionary = (a["src"] as Dictionary).get("attack_rules", {})
		return float((rules.get(key, {}) as Dictionary).get("cooldown", 0.0))
	return 0.0


# ---------- 演示 / 动作按钮 ----------

func _make_portrait(path: String) -> void:
	_portrait = TextureRect.new()
	_portrait.texture = load(path)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(STAGE_X, STAGE_Y)
	_portrait.size = Vector2(STAGE_W, STAGE_H)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)


func _make_preview(data, view_scale: float, idle: String) -> void:
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.0 if _tab == TAB_ENEMY and _sel == "c016" else 0.2)
	sprite.scale = Vector2(view_scale, view_scale)
	sprite.position = Vector2(SPRITE_X, SPRITE_Y)
	_preview = sprite
	if _tab == TAB_ENEMY and _sel == "c016":
		_pose_mixer = SpinePoseMixer.new(sprite)
	_idle_anim = idle
	_play(idle)


func _anim_names(data) -> Dictionary:
	var out := {}
	for a in data.call("get_animations"):
		out[str(a.call("get_name"))] = true
	return out


func _make_action_button(a: Dictionary, i: int) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(BTN_W, BTN_H)
	b.position = Vector2(BTN_X + (i % BTN_COLS) * (BTN_W + BTN_GAP), BTN_Y + int(i / BTN_COLS) * BTN_STEP_Y)
	b.pressed.connect(_pick.bind(i))
	b.mouse_entered.connect(_on_btn_hover.bind(i))
	b.mouse_exited.connect(_on_btn_unhover.bind(i))
	add_child(b)

	# 选中反馈：左缘一道朱砂细条
	var bar := ColorRect.new()
	bar.color = RED
	bar.size = Vector2(4, BTN_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	b.add_child(bar)

	var l := Label.new()
	l.text = str(a["label"])
	l.size = Vector2(BTN_W, BTN_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)

	_act_btns.append(b)
	_act_bars.append(bar)
	_act_labels.append(l)


## 点击某条动作：演示台播它的动画，解析面板写对应资料；多变式由 ↑ / ↓（手机再点一次）切换
func _pick(i: int) -> void:
	if i < 0 or i >= _acts.size():
		return
	if i == _pick_idx and OS.has_feature("mobile") and _pool.size() > 1:
		_cycle_pool(1) # 手机没有方向键：同一招式再点一次就是切下一个变式
		_click_sfx()
		return
	var a: Dictionary = _acts[i]
	_pick_idx = i
	_pool = a["anims"]
	_pool_i = 0
	_click_sfx()

	var anim := _idle_anim
	if not _pool.is_empty():
		anim = str(_pool[0])
	_play(anim, a.get("sequence", []), bool(a.get("death_finisher", false)))
	if bool(a.get("death_finisher", false)):
		_preview_death_finisher(i)
	_desc_rt.text = _desc_text(a, anim)
	_refresh_btns()


func _preview_death_finisher(pick: int) -> void:
	await get_tree().create_timer(3.467).timeout
	if _preview == null or not is_instance_valid(_preview) or _pick_idx != pick or _current_anim != "transform":
		return
	var origin: Vector2 = _preview.position
	var slash := create_tween()
	slash.set_parallel(true)
	slash.tween_property(_preview, "rotation", -0.22, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slash.tween_property(_preview, "position:x", origin.x + 72.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.14).timeout
	if _preview == null or not is_instance_valid(_preview):
		return
	if _pick_idx != pick:
		_preview.rotation = 0.0
		_preview.position = origin
		return
	var recover := create_tween()
	recover.set_parallel(true)
	recover.tween_property(_preview, "rotation", 0.0, 0.26)
	recover.tween_property(_preview, "position:x", origin.x, 0.26)
	await get_tree().create_timer(0.30).timeout
	if _preview != null and is_instance_valid(_preview) and _pick_idx == pick:
		_play(_idle_anim)


## 上 / 下键在当前动作的变式池中循环选择；不自动跳转，选中的动画持续循环播放
func _cycle_pool(step: int) -> void:
	if _pick_idx < 0 or _pool.size() <= 1:
		return
	if _desc_rt == null or not is_instance_valid(_desc_rt):
		return
	_pool_i = posmod(_pool_i + step, _pool.size())
	var anim := str(_pool[_pool_i])
	_play(anim)
	var a: Dictionary = _acts[_pick_idx]
	_desc_rt.text = _desc_text(a, anim)


func _refresh_btns() -> void:
	for i in mini(_act_btns.size(), _act_labels.size()):
		var lit := i == _pick_idx or i == _hover_idx
		_act_bars[i].visible = i == _pick_idx
		var tex := "res://art/ui/menu/btn_clicked.png" if lit else "res://art/ui/menu/btn_normal.png"
		(_act_btns[i] as TextureButton).texture_normal = InkTex.load(tex)
		# 墨牌底色统一为深墨，选中/悬停用金边与朱线区分，字始终用浅纸色
		(_act_labels[i] as Label).add_theme_color_override("font_color", PAPER)


func _on_btn_hover(i: int) -> void:
	_hover_idx = i
	_refresh_btns()


func _on_btn_unhover(i: int) -> void:
	if _hover_idx == i:
		_hover_idx = -1
		_refresh_btns()


## 解析面板文案：标题（含变式 x/n 与切换提示）+ 数值 / 机制 / 冷却 / 来历
func _desc_text(a: Dictionary, anim: String) -> String:
	var lines: Array = []
	var head := "[b]%s[/b]" % str(a["label"])
	var pool: Array = a["anims"]
	if pool.size() > 1:
		var how := "再点一次切换" if OS.has_feature("mobile") else "↑ / ↓ 切换"
		head += "  [color=#b07a2c]· 变式 %d/%d · %s[/color]" % [_pool_i + 1, pool.size(), how]
	lines.append(head)

	var kind := str(a["kind"])
	if kind == "passive":
		var passive: Dictionary = (a["src"] as Dictionary).get("passive", {})
		if not passive.is_empty():
			lines.append("[color=#a8332a]被动技能 · %s[/color]" % str(passive["name"]).replace(" ", ""))
			lines.append("[color=#8a857a]机制：[/color]" + str(passive["desc"]))
			lines.append("[color=#8a857a]来历：[/color]" + str(passive["lore"]))
		return "\n".join(lines)
	if kind == "act":
		lines.append("[color=#8a857a]角色通用动作，仅作演示。[/color]")
		return "\n".join(lines)
	if kind == "transform":
		lines.append("[color=#8a857a]机制：[/color]" + _mech_for(a))
		return "\n".join(lines)

	var num := _num_for(a, anim)
	if num != "":
		lines.append("[color=#8a857a]数值：[/color]" + num)
	var mech := _mech_for(a)
	if mech != "":
		lines.append("[color=#8a857a]机制：[/color]" + mech)
	var cd := _cd_for(a)
	if cd > 0.0:
		lines.append("[color=#8a857a]冷却：[/color]%.1f 秒" % cd)
	var origin := str(a.get("lore", ""))
	if kind == "enemy_atk":
		var key := str(a.get("key", anim))
		origin = str((ENEMY_ATTACK_LORE.get(str(a.get("id", "")), {}) as Dictionary).get(key, ""))
	if not origin.is_empty():
		lines.append("[color=#8a857a]来历：[/color]" + origin)
	return "\n".join(lines)


func _process(delta: float) -> void:
	if _pose_mixer == null or _preview == null or not is_instance_valid(_preview):
		return
	var step := delta
	if not _pending_anim.is_empty():
		var st = _preview.call("get_animation_state")
		st.call("set_animation", _pending_anim, not bool(_preview.get_meta("codex_hold_last", false)), 0)
		_pending_anim = ""
		step = 0.0
	_pose_mixer.update(step)


func _play(anim: String, sequence: Array = [], hold_last := false) -> void:
	if _preview == null or not is_instance_valid(_preview) or anim == "":
		return
	var chained := sequence.size() > 1
	# 循环动作重复点击不重开；连段则允许演完后再次点击，从头完整重演。
	if anim == _current_anim and not chained:
		return
	_current_anim = anim
	var st = _preview.call("get_animation_state")
	if st == null:
		return
	_preview.set_meta("codex_hold_last", hold_last)
	if _pose_mixer != null:
		_pose_mixer.capture()
		_pending_anim = anim
		return
	st.call("set_animation", anim, not chained and not hold_last, 0)
	if chained:
		for i in range(1, sequence.size()):
			st.call("add_animation", str(sequence[i]), 0.0, false, 0)
		st.call("add_animation", _idle_anim, 0.0, true, 0) # 完整连段演完回待机，不循环第一小段


func _set_portrait_view(enabled: bool) -> void:
	if _show_portrait == enabled:
		return
	_show_portrait = enabled
	call_deferred("_refresh")


func _select(id: String) -> void:
	if _sel == id:
		return
	_sel = id
	_show_portrait = true
	_click_sfx()
	call_deferred("_refresh")


func _switch_tab(tab: int) -> void:
	if _tab == tab:
		return
	_tab = tab
	_sel = ""
	# 先清空旧控件的真实滚动值，避免 _refresh 又把旧页位置捕获回来。
	if is_instance_valid(_status_list):
		_status_list.scroll_vertical = 0
	if is_instance_valid(_story_list):
		_story_list.scroll_vertical = 0
	_status_scroll = 0
	_story_scroll = 0
	_show_portrait = true
	_click_sfx()
	call_deferred("_refresh")


## 图鉴音乐开关：开 → 独占播放图鉴曲（压掉主菜单 BGM）；关 → 停掉图鉴曲，恢复主菜单 BGM。
func _toggle_music() -> void:
	_music_on = not _music_on
	if _music_on:
		BGM.play_solo(CODEX_MUSIC)
	else:
		BGM.stop_solo()
	if not is_instance_valid(_music_btn):
		return
	# 只重绘这一个按钮：全量 _refresh 会重置当前招式演示与滚动位置
	_music_btn.texture_normal = InkTex.load("res://art/ui/menu/btn_clicked.png" if _music_on else "res://art/ui/menu/btn_normal.png")
	var label := _music_btn.get_child(0) as Label
	if label != null:
		label.text = "音 乐 · " + ("开" if _music_on else "关")
		label.add_theme_color_override("font_color", RED if _music_on else PAPER)


# ---------- 控件 ----------

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.34)
	s.border_color = Color(1, 1, 1, 0.2)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _make_label(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _entry_label(parent: Control, text: String, y: float, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(parent.size.x, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)


func _make_button(text: String, pos: Vector2, size: Vector2, font_size: int, cb: Callable, active := false, sfx: AudioStream = SFX_CLICK) -> TextureButton:
	# 选中页签用按下态底图当常态，形成「压在纸上」的反色效果
	var normal := UiKit.BTN_PRESSED if active else UiKit.BTN_NORMAL
	var act := func():
		_play_sfx(sfx)
		cb.call()
	return UiKit.texture_button(self, text, pos, size, font_size, RED if active else PAPER,
		act, normal, UiKit.BTN_NORMAL)


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


## 点击音：复用常驻播放器（重建不清它），不每次点击都新建节点
func _click_sfx() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()
