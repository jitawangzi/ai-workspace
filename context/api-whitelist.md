# 项目 API 历史快照

从旧 context 保留的 API 签名与说明。使用前对照当前源码；不能因快照过期而修改已经正确的实现。原始文件保留在 `.claude_old/context/api-whitelist.md`。

```java
// ==========================================
// AI Context Export
// Workspace: 本项目根目录（相对路径）
// Modules: game, login, util
// ==========================================

// --- Class: DbEntity ---
    /**
     * 数据库实体接口，所有数据库实体类都需要实现这个接口。
     * 这个接口定义了一些基本的数据库操作方法，如插入、更新、删除等。
     * 这些方法都是异步的，返回一个Future对象，表示操作的结果。
     * 具体实现由DAO类提供，DAO类负责与数据库进行交互。
     * 2024年4月8日 下午6:45:47
     *
     * @author SYQ
     */
public class DbEntity {
    public Future<@Nullable Object> insert();

    public Future<@Nullable Object> insertOrUpdate();

    /**
     * 更新整行数据
     *
     * @return
     */
    public Future<@Nullable Object> update();

    public Future<@Nullable Object> delete();

    public Class<?> getMapperClass();

    /**
     * 这里为什么要单独抽取出来方法，是因为希望这个方法在客户端eventloop线程执行，
     * 而不是在vertx的worker线程池里执行，否则会多个线程同时读写map之类，容易有线程安全问题。
     * 这里这类对象都是在同一个进程里读写的。
     */
    public void beforeSave();

    public abstract Object primaryKey();

}

// --- Class: Player ---
public class Player {
    public T getModule(Class<T> clazz);

    /**
     * 周期性的运行某一任务
     *
     * @param delay 间隔时间（ms）
     * @param handler
     * @return
     */
    public long setPeriodicTask(long delay, Handler<Player> handler);

    /**
     * 延迟一段时间后，执行一个任务
     *
     * @param delay 延迟时间（ms）
     * @param handler
     * @return
     */
    public long setTimerTask(long delay, Handler<Player> handler);

    public void cancelTimer(long id);

    public void cancelAllTimer();

    /**
     * 注册事件处理器
     */
    public void registerEventHandler(PlayerEventHandler handler);

    public void registerEventHandler(EventTypeEnum eventType, EventProcessor<PlayerEvent> handler);

    public void fireAndHandleEvent(EventTypeEnum eventType);

    public void fireAndHandleEvent(EventTypeEnum eventType, Object... params);

    public PlayerEventBus getPlayerEventBus();

    public boolean isEnough(int id, int count);

    /**
     * 支付，有可能支付普通货币，也有可能支付rmb
     * 一般普通货币支付的，尽量不要调用这个方法，这个方法尽量处理rmb支付的。
     *
     * @param payType 支付类型，购买的什么类型的东西
     * @param id 针对支付类型的id，例如购买月卡，id就是月卡id
     * @param cost 费用，第一个是支付类型，第二个是支付的id，第三个是支付的数量
     * @param otherId 其他id,例如活动id等
     * @return
     */
    public Future<Boolean> pay(PayType payType, int id, int[] cost, int... otherId);

    /**
     * 包含广告和普通货币的购买，不涉及到rmb支付
     *
     * @param cost
     * @return
     */
    public void pay(int[] cost, OpType opType);

    /**
     * 获取福利的加成值
     *
     * @param type
     * @return
     */
    public int getWelfareValue(WelfareTypeEnum type);

    /**
     * 是否有某种福利
     *
     * @param type
     * @return
     */
    public boolean hasWelfare(WelfareTypeEnum type);

    /**
     * 某个功能是否开启了
     *
     * @param type
     * @return
     */
    public boolean isFuncOpen(InitialUI type);

    /**
     * 获取玩家等级
     *
     * @return
     */
    public int getLevel();

    public void handleFail(Throwable t);

    /**
     * 处理客户端请求出现的异常 ，发送默认错误返回并记录异常日志。
     * 一般用在异步调用的异常处理
     *
     * @param response 发生错误时的返回消息
     * @param t 异常
     */
    public void handleFail(Message response, Throwable t);

    /**
     * 处理function类型的异步调用异常
     *
     * @param t 异常
     * @return null
     */
    public T handleFailFunction(Throwable t);

    /**
     * 主动抛出一个错误，中断当前流程。
     *
     * @param errorMsgEnum
     */
    public void fail(ErrorMsgEnum errorMsgEnum);

    /**
     * 检查客户端输入的数量范围，是否在合法范围内
     *
     * @param count
     */
    public void checkClientRequestCount(int count);

    public PlayerData getData();

    public GameClient getGameClient();

    public Account getAccount();

}

// --- Class: PlayerHelper ---
public class PlayerHelper {
    /**
     * 判断玩家是否有足够的物品
     *
     * @param player
     * @param list entry key:物品id,entry value:数量
     * @return
     */
    public static boolean isEnough(Player player, Collection<? extends Entry<Integer, Integer>> list);

    /**
     * 判断玩家是否有足够的物品
     *
     * @param player
     * @param map key:物品id, value:数量
     * @return
     */
    public static boolean isEnough(Player player, Map<Integer, Integer> map);

    /**
     * 判断玩家是否有足够的物品
     *
     * @param player
     * @param list ，数组0是id，1是数量
     * @return
     */
    public static boolean isEnough(Player player, int[][] list);

    /**
     * 判断玩家是否有足够的物品
     *
     * @param player
     * @param list ，数组0是id，1是数量，也可以向后扩展，例如 2是id，3是数量
     * @return
     */
    public static boolean isEnough(Player player, int[] list);

    /**
     * 判断玩家是否有足够的物品
     *
     * @param player
     * @param id 物品id，可能是({@link Asset#ID}) 或者是({@link ItemConfig#ID}) ({@link HeroConfig#ID})等等的id
     * 通过物品id的规则，计算出属于什么物品类型
     * 所有物品类型 : {@link GoodsTypeEnum#getId()}
     * @param count
     * @return
     */
    public static boolean isEnough(Player player, int id, int count);

    /**
     *
     * @param player
     * @param consumeId : {@link ConsumeConfig#ID}
     * @return
     */
    public static boolean isEnough(Player player, int consumeId);

    /**
     * 给某玩家增加物品
     *
     * @param player
     * @param id 物品id，可能是({@link Asset#ID}) 或者是({@link ItemConfig#ID}) ({@link HeroConfig#ID})等等的id
     * @param value 增加数量
     * @param opType 操作类型
     * @param notify 增加后，是否通知客户端
     * @return
     */
    public static List<RewardInfo> addResources(Player player, int id, int value, OpType opType, boolean notify);

    public static List<RewardInfo> addResources(Player player, int id, int value, OpType opType);

    public static List<RewardInfo> addResources(Player player, int id, int value);

    /**
     * 扣除玩家的物品
     *
     * @param player
     * @param id 物品id，可能是({@link Asset#ID}) 或者是({@link ItemConfig#ID}) ({@link HeroConfig#ID})等等的id
     * @param value 减少的数量
     * @param consumeType 消耗类型
     */
    public static void delResources(Player player, int id, long value, OpType consumeType);

    /**
     * 通过消耗表的id，来扣除玩家的物品
     *
     * @param player
     * @param consumeId 消耗表的id  {@link ConsumeConfig#ID}
     * @param consumeType 消耗类型
     * @return
     */
    public static void delResourcesWithConsume(Player player, int consumeId, OpType consumeType);

    /**
     * 通过消耗表的id，来扣除玩家的物品
     *
     * @param player
     * @param consumeId 消耗表的id  {@link ConsumeConfig#ID}
     * @param multiple 倍数
     * @param consumeType 消耗类型
     * @return
     */
    public static void delResourcesWithConsume(Player player, int consumeId, int multiple, OpType consumeType);

    /**
     * 进行某操作时扣除资源，包括所有大类型
     *
     * @param player
     * @param id 物品id，可能是({@link Asset#ID}) 或者是({@link ItemConfig#ID}) ({@link HeroConfig#ID})等等的id
     * @param value 减少的数量
     * @param consumeType 消耗类型
     * @param notify 是否通知客户端  如果直接调用该方法不涉及合并问题则传true, 如果涉及合并则传false，合并后需要推送协议SpendPush_55001501
     */
    public static void delResources(Player player, int id, long value, OpType consumeType, boolean notify);

    /**
     * 进行某操作时扣除资源，包括所有大类型
     *
     * @param player 玩家
     * @param list，entry key:物品id,entry value:数量
     * @param consumeType 消耗类型
     */
    public static void delResources(Player player, Collection<? extends Entry<Integer, Integer>> list, OpType consumeType);

    /**
     * 进行某操作时扣除资源，包括所有大类型
     *
     * @param player
     * @param map，key:物品id,value:数量
     * @param consumeType 消耗类型
     * @throws LogicException 当资源不足时，默认抛出异常中断当前流程，如果不想出现异常，需要先调用isEnough 方法进行判断
     */
    public static void delResources(Player player, Map<Integer, Integer> map, OpType consumeType);

    /**
     * 进行某操作时扣除资源，包括所有大类型
     *
     * @param player
     * @param list ，数组0是id，1是数量
     * @param consumeType
     * @return
     */
    public static void delResources(Player player, int[][] list, OpType consumeType);

    /**
     * 进行某操作时扣除资源，包括所有大类型
     *
     * @param player
     * @param list ，数组0是id，1是数量,也可以向后扩展，例如 2是id，3是数量
     * @param consumeType
     * @throws LogicException 当资源不足时，默认抛出异常中断当前流程，如果不想出现异常，需要先调用isEnough 方法进行判断
     */
    public static void delResources(Player player, int[] list, OpType consumeType);

    /**
     * 根据奖励id，增加所有物品
     *
     * @param player
     * @param randomRewardId {@link RandomGivenConfig#ID}
     * @return
     */
    public static List<RewardInfo> addReward(Player player, int randomRewardId, OpType opType);

    /**
     * 根据奖励id，增加所有物品,带加成
     *
     * @param player
     * @param randomRewardId {@link RandomGivenConfig#ID}
     * @param additionValue,额外增加的数量加成， 除以10000
     * @return
     */
    public static List<RewardInfo> addReward(Player player, int randomRewardId, int additionValue, OpType opType);

    /**
     * 只是随机出来具体的奖励，不加到玩家身上,较少直接用到
     *
     * @param randomRewardId {@link RandomGivenConfig#ID}
     * @return
     */
    public static List<Goods> randomReward(int randomRewardId);

    /**
     * 一次性增加多个奖励
     *
     * @param player
     * @param goods
     * @return
     */
    public static List<RewardInfo> addResources(Player player, List<Goods> goods, OpType opType);

    public static List<RewardInfo> addResources(Player player, int[][] rewards, OpType opType);

    public static List<RewardInfo> addGoods(Player player, List<Goods> goods, OpType opType);

    public static List<RewardInfo> addResources(Player player, int[][] rewards, OpType opType, boolean notify);

    public static List<RewardInfo> addResources(Player player, int[] rewards, OpType opType);

    /**
     * 一次性增加多个奖励，增加完奖励后推送给客户端一次。
     *
     * @param player
     * @param rewards
     * @return
     */
    public static List<RewardInfo> addResources(Player player, Collection<? extends Entry<Integer, Integer>> rewards, OpType opType);

    public static List<RewardInfo> addResources(Player player, Map<Integer, Integer> map, OpType opType);

    /**
     * 主动给玩家发送消息
     *
     * @param playerId
     * @param message
     */
    public static void sendProtocol(long playerId, Object message);

    /**
     * 给玩家发消息，带错误码
     *
     * @param playerId
     * @param message 消息
     * @param errorCode 错误码
     */
    public static void sendProtocol(long playerId, Object message, int errorCode);

    /**
     * 给玩家发默认的错误消息，带错误码
     *
     * @param playerId
     * @param errorCode 错误码
     */
    public static void sendErrorProtocol(long playerId, int errorCode);

    /**
     * 将消息发送给指定服务器的玩家，不需要返回消息
     *
     * @param playerId 目标玩家id
     * @param message
     * @param serverId 目标服务器id
     */
    public static void sendToRemotePlayer(long playerId, String serverId, Message message);

    /**
     * 将消息广播给跨服玩家
     *
     * @param message
     * @param playerIds
     * @param serverIds
     */
    public static void sendToRemotePlayers(Message message, List<Long> playerIds, List<String> serverIds);

    /**
     * 是否满足所有条件
     *
     * @param player
     * @param conditions 待检查条件，  {@link ConditionConfig#ID}
     * @return
     */
    public static boolean checkCondition(Player player, int... conditions);

    /**
     * 是否满足所有条件
     *
     * @param player
     * @param conditions 待检查条件，  {@link ConditionConfig#ID}
     * @param or 是否满足任意条件即可
     * @return true,如果满足任意条件
     */
    public static boolean checkCondition(Player player, boolean or, int... conditions);

    /**
     * 基础的条件检查
     *
     * @param player
     * @param condition 待检查条件，  {@link ConditionConfig#ID}
     * @return
     */
    public static boolean checkCondition(Player player, int condition);

    /**
     * 获取某条件的计数，一般是根据当前数据直接可以获得的，或者是累计计数等，不需要额外条件的。
     *
     * @param player
     * @param condition 待检查条件，  {@link ConditionConfig#ID}
     * @return
     */
    public static long getConditionCount(Player player, int condition);

    /**
     * 获取某个升级配置。
     *
     * @param id 经验id
     * @param level 等级
     * @param subId 子id，如果同一类型下有多个配置，用这个区分。
     * @return
     */
    public static ExpConfig getExpConfig(int id, int level, int subId);

    /**
     * 获取玩家的逻辑服务器id
     *
     * @param playerId
     * @return
     */
    public static String getServerId(long playerId);

}

// --- Class: PlayerManager ---
public class PlayerManager {
    /**
     * 获取指定角色id的角色数据
     *
     * @param playerId
     * @return
     */
    public Player getPlayer(long playerId);

    public ConcurrentHashMap<Long, Player> getAllPlayer();

}

// --- Class: DateUtil ---
    /**
     * 2016-7-8 下午4:46:08
     *
     * @author SYQ
     */
public class DateUtil {
    /**
     *
     * @param textDate
     * @return
     */
    public static Date parseDate(String textDate);

    public static LocalDateTime parse(String textDate);

    /**
     * 将 Date 转换为指定格式字符串
     */
    public static String getTimeByPattern(Date time, String pattern);

    public static long howLong(TimeUnit unit, Date date1, Date date2);

    public static long howLong(TimeUnit unit, long time1, long time2);

    /**
     * 获取当前时间字符串
     */
    public static String getStringDate();

    /**
     * 将时间字符串转为毫秒时间戳
     */
    public static long getLongDate(String dateString);

    /**
     * 获取当前时间 n天后0点的毫秒时间戳
     *
     * @param days 天数
     * @return 毫秒时间戳
     */
    public static long nextDayStartTime(int days);

    /**
     * 获取当前时间 n天后0点的秒时间戳
     *
     * @param days 天数
     * @return 秒时间戳
     */
    public static int nextDayStartTimeSecond(int days);

    /**
     * n天后的0点开始时间戳
     *
     * @param startTime 开始时间戳（毫秒）
     * @param days 天数
     * @return 毫秒时间戳
     */
    public static long nextDayStartTime(long startTime, int days);

    /**
     * 获取当天指定时间的时间戳
     *
     * @param hourOffset 0--23 小时
     * @param minuteOffset 0--59 分钟
     * @param secondOffset 0--59 秒
     * @return 毫秒时间戳
     */
    public static long getDayTimeBySet(int hourOffset, int minuteOffset, int secondOffset);

    /**
     * 获取指定时间那天的指定时间的时间戳
     *
     * @param timer 毫秒时间戳
     * @param hourOffset 0--23 小时
     * @param minuteOffset 0--59 分钟
     * @param secondOffset 0--59 秒
     * @return 设置后的时间戳（毫秒）
     */
    public static long getTimeBySet(long timer, int hourOffset, int minuteOffset, int secondOffset);

    /**
     * 获取指定日期时间的天数（相对于起始日期）
     * 以凌晨5点为一天的开始
     */
    public static int getDayCustom(LocalDateTime dateTime);

    /**
     * 获取当前的天数（相对于起始日期）
     * 以凌晨5点为一天的开始
     */
    public static int getDayCustom();

    /**
     * 获取当前天数（相对于起始日期）
     *
     * @return
     */
    public static int getDay();

    /**
     * 获取指定日期的天数（相对于起始日期）
     */
    public static int getDayNumber(LocalDate date);

    /**
     * 获取当前日期的“全局周序号”
     */
    public static int getWeek();

    /**
     * 获取当前日期的“全局月序号”
     *
     * @return
     */
    public static int getMonth();

    /**
     * 判断两个日期时间是否在同一个业务日
     */
    public static boolean isSameBusinessDay(LocalDateTime dateTime1, LocalDateTime dateTime2);

    public static long addWeekBeginTimer(int offsetWeek);

    /**
     * 获取当前日期的字符串格式
     *
     * 格式: yyyy-mm-dd
     *
     * @return 当前日期的字符串格式
     */
    public static String nowDateStr();

    /**
     * 判断当前时间是否在两个时间之内
     *
     * @param start
     * @param end
     * @return
     */
    public static boolean between(Date start, Date end);

    /**
     * 获取当前时间的字符串格式
     * 格式: HH:mm:ss
     *
     * @return 当前时间的字符串格式
     */
    public static String nowTimeStr();

    /**
     * 计算当前时间与特定时间之间相隔的天数（日期数）
     *
     * @param timeMillis
     * @return
     */
    public static int diffDays(long timeMillis);

    /**
     * 计算两个时间戳之间相隔的天数（日期数）
     *
     * @param t1 第一个时间戳
     * @param t2 第二个时间戳
     * @return 相差的天数
     */
    public static int diffDays(long t1, long t2);

    /**
     * 计算两个日期之间的天数差,同一天返回0
     *
     * @param date1 第一个日期
     * @param date2 第二个日期
     * @return 相差的天数
     */
    public static int diffDays(LocalDate date1, LocalDate date2);

    /**
     * 计算两个日期之间的时间差,同一天返回0
     *
     * @param date1
     * @param date2
     * @param unit 时间单位
     * @return
     */
    public static int diffDays(LocalDate date1, LocalDate date2, ChronoUnit unit);

    public static int diff(LocalDateTime time1, LocalDateTime time2, ChronoUnit unit);

    /**
     * 计算当前时间和特定时间之间相隔的时间差
     *
     * @param timeMillis
     * @param unit
     * @return
     */
    public static int diff(long timeMillis, ChronoUnit unit);

    /**
     * 判断俩时间戳 是否为同一天
     *
     * @param t1
     * @param t2
     * @return true 是同一天 ； false 不是同一天
     */
    public static boolean isSameDay(long t1, long t2);

    public static boolean isSameDay(LocalDateTime t1, LocalDateTime t2);

    /**
     * 获取当天的指定小时 整分整秒的时间戳
     *
     * @param hour 小时（0-23）
     * @return 毫秒时间戳
     */
    public static long getDayHourTimestamp(int hour);

    /**
     * 获取指定日期的指定小时时间戳
     *
     * @param date 指定日期
     * @param hour 小时（0-23）
     * @return 毫秒时间戳
     */
    public static long getDayHourTimestamp(LocalDate date, int hour);

    /**
     * 计算当前时间与特定时间之间相隔的天数（日期数）
     *
     * @param dateTimeStr "yyyy-MM-dd HH:mm:ss"  格式
     * @return
     */
    public static int diffDays(String dateTimeStr);

    public static int currentTimeSeconds();

    public static long currentTimeMillis();

    /**
     * 将LocalDateTime转换为时间戳
     */
    public static long toEpochMilli(LocalDateTime localDateTime);

    /**
     * 将LocalDateTime转换为秒级时间戳
     *
     * @param localDateTime
     * @return
     */
    public static int toEpochSecond(LocalDateTime localDateTime);

    /**
     * 将时间戳转换为LocalDate
     */
    public static LocalDate toLocalDate(long timestamp);

    /**
     * 将时间戳转换为LocalDateTime
     */
    public static LocalDateTime toLocalDateTime(long timestamp);

    /**
     * 按 period*periodPass 秒修改 date
     */
    public static Date changeDateByPeriod(Date date, int period, int periodPass);

    public Date changeDateByPeriod2(Date date, int period, int periodPass);

    /**
     *
     * @param args
     */
    public static void main(String[] args);

}

// --- Class: GameUtil ---
    /**
     * 一些常用方法
     * 2022年4月12日 下午12:12:57
     *
     * @author SYQ
     */
public class GameUtil {
    public static List<Long> transform(List<Integer> list);

    public static int[] transformList(List<Integer> list);

    public static List<Long> transform(int[] array);

    public static String[] transformToStringArray(List<Long> list);

    public static List<Integer> transform1(int[] array);

    public static long[] transformArray(int[] array);

    /**
     * 是否包含
     */
    public static boolean contains(int[] array, int o);

    /**
     * 是否包含
     */
    public static boolean contains(String[] array, String o);

    public static boolean containsAll(List<Integer> list, int[] array);

    /**
     * 给数量做加成
     *
     * @param array 0：id 1：数量
     * @param addition,加成值，除10000使用
     * @return
     */
    public static int[] arrayAddition(int[] array, int addition);

    /**
     * 按万分比对数量进行缩放（正数=增加，负数=减少）
     *
     * @param array 二维数组：每行 [id, 数量, id, 数量, ...]
     * @param rate 万分比，正数增加，负数减少，例如 500 表示 +5%，-250 表示 -2.5%
     * @return 新数组（不会修改入参）
     */
    public static int[][] arrayZoomBy10k(int[][] array, int rate);

    /**
     * 给数量做增加
     *
     * @param array 0：id 1：数量
     * @param addition
     * @param multiple
     * @return
     */
    public static int[][] arrayAddition(int[][] array, int[] addition, int multiple);

    /**
     * 给数量做倍数
     *
     * @param array 0：id 1：数量
     * @param multiple 倍数
     * @return
     */
    public static int[] arrayMultiple(int[] array, int multiple);

    /**
     * 给数量做倍数
     *
     * @param array 0 类型  1：id 2：数量
     * @param multiple 倍数
     * @return
     */
    public static int[] arrayMultiple3(int[] array, int multiple);

    /**
     * 给数量做倍数
     *
     * @param array 0：id 1：数量
     * @param multiple 倍数
     * @return
     */
    public static int[][] arrayMultiple(int[][] array, int multiple);

    /**
     * 合并两个数组，result中相同id的数量加上add中的数量
     * 需要确保id的顺序是一致的,例如：
     * arr1
     * 		202002;10
     * 		202003;10
     * 		202004;20
     * 		202005;20
     *
     * 		arr2
     * 		202002;30
     * 		202003;30
     *
     * @param result 结果
     * @param add 增加的数据（不可变类型）
     * @return
     */
    public static int[][] fastMergeAddPrefix(int[][] result, int[][] add);

    /**
     * 合并两个数组，result中相同id的数量加上add中的数量
     *
     * @param result 结果
     * @param add 增加的数据（不可变类型）
     * @return
     */
    public static int[][] mergeAdd(int[][] result, int[][] add);

    /**
     * 合并两个数组：对相同id进行数量减少，最少减到0；不生成负数条目；
     * 若某条数量为0，保留该条。
     * 输入要求：result 与 sub 按 id 升序且 id 唯一。
     *
     * @param result 已有数据
     * @param sub 要减少的数据（不可变类型）
     * @return 合并后的数组（按id升序）
     */
    public static int[][] mergeSubtractFloorZeroKeepZero(int[][] result, int[][] sub);

    public static int[] transformIdAndCount(List<Integer> idList, List<Integer> countList);

    /**
     * 是不是同一个大版本
     *
     * @param version1
     * @param version2
     * @return
     */
    public static boolean equalsVersion(String version1, String version2);

    /**
     * 从 drops 中减去 items 包含的道具数量
     *
     * @param drops 原始掉落奖励
     * @param items 需要减去的道具数量
     * @return
     */
    public static int[][] subItems(int[][] drops, int[][] items);

    /**
     * 计算输入字符串的 MD5 十六进制结果
     *
     * @param input 输入字符串
     * @return MD5 哈希的 16 进制字符串
     */
    public static String md5Hex(String input);

    /**
     * 解析server id，使用程序运行时参数或者环境变量设置的server id
     *
     * @param args
     * @param serverType
     * @return
     */
    public static String parseServerId(String[] args, ServerType serverType);

    /**
     * 获取一个数组中，大于0的元素个数
     *
     * @param array
     * @return
     */
    public static int length(int[] array);

    /**
     * 获取一个数组中，只是0的元素个数
     *
     * @param array
     * @return
     */
    public static int zeroLength(int[] array);

    public static int[] getArrayCost(int[][] array, int count);

    public static int getArrayCost(int[] array, int count);

}

// --- Class: JsonUtil ---
    /**
     * 对jackson的一个封装
     * 2024年3月1日 下午5:14:33
     *
     * @author SYQ
     */
public class JsonUtil {
    /**
     * 对象转成json字符串，默认不带类型信息的序列化（常用）
     *
     * @param value
     * @return
     */
    public static String toJsonString(Object value);

    /**
     * 对象转成json字符串，带有类的类型信息
     * 方便反序列化时获取精确类型。 （特殊场景使用）
     *
     * @param value
     * @return
     */
    public static String toJsonStringWithType(Object value);

    /**
     * 解析json字符串成对象，需要注意正确的对象类型
     *
     * @param <T>
     * @param value
     * @param valueType
     * @return
     */
    public static T parseObject(String value, Class<T> valueType);

    /**
     * 反序列化带有类型信息的json字符串
     *
     * @param value json字符串
     * @return 反序列化后的对象
     */
    public static T parseObjectWithType(String value);

}

// --- Class: RedisUtil ---
    /**
     * Redisson操作工具类，封装常用方法
     *
     * 后续看看增加Vert.x的Redis客户端，回调线程更自然。
     * 2021年3月11日 下午3:07:23
     *
     * @author SYQ
     */
public class RedisUtil {
    /**
     * 使用高级功能如集合等等，可以获取redis实例进行操作，一般的存储读取使用封装好的方法
     *
     * @return
     */
    public static RedissonClient getRedis();

}

// --- Class: Rnd ---
    /**
     *
     * @ClassName: Rnd
     * @Description: 随机数生成帮助类
     * @author luopeihuai luopeihuai@126.com
     * 2010-12-17 下午02:02:48
     */
public class Rnd {
    /**
     *
     * @Title: get
     * @Description: 随机生成一个0到1(不包括)的数
     * @return double 返回类型
     * @throws
     */
    public static final double get();

    /**
     *
     * @Title: get
     * @Description: 得到一个 min <= x <= max的随机数
     * @param min
     * @param max
     * @return int 返回类型 @throws
     */
    public static final int get(int min, int max);

    /**
     * 得到一个 min <= x <= max的随机奇数
     *
     * @param min
     * @param max
     * @return
     */
    public static final int getOdd(int min, int max);

    /**
     *
     * @Title: nextInt
     * @Description: 得到一个 0 到 n-1的随机数
     * @param n
     * @return int 返回类型 @throws
     */
    public static final int nextInt(int n);

    /**
     * 返回一个 >= min, < max 的随机数
     *
     * @param min
     * @param max
     * @return
     */
    public static final int nextInt(int min, int max);

    /**
     *
     * @Title: nextFloat
     * @Description: 得到一个 (0 -f] 的随机数
     * @param n
     * @return float 返回类型 @throws
     */
    public static final float nextFloat(float f);

    /**
     *
     * @Title: nextInt
     * @Description: 随机生成一个整形数
     * @return int 返回类型
     * @throws
     */
    public static final int nextInt();

    public static final long nextLong();

    /**
     *
     * @Title: nextDouble
     * @Description: 生成一个双精度值 0.0d（包括）到 1.0d（不包括）
     * @return double 返回类型
     * @throws
     */
    public static final double nextDouble();

    /**
     *
     * @Title: nextDouble
     * 生成一个双精度值 ,from（包括）到 to（包括）
     * @return double 返回类型
     * @throws
     */
    public static final double nextDouble(double from, double to);

    /**
     *
     * @Title: nextGaussian
     * @Description: 生成一个高斯双精度值
     * @return double 返回类型
     * @throws
     */
    public static final double nextGaussian();

    /**
     *
     * @Title: nextBoolean
     * @Description: 生成随机布尔值
     * @return boolean 返回类型
     * @throws
     */
    public static final boolean nextBoolean();

    /**
     *
     * @Title: nextBytes
     * @Description: 初始化数组
     * @param array
     * @return void
     * @throws
     */
    public static final void nextBytes(final byte[] array);

    /**
     * 根据奖励库类别随机出来奖励物品
     */
    public static int randomIndex(int[] weight);

    /**
     * 按照一个集合里面元素的权重随机。
     *
     * @param <T>
     * @param list
     * @param function
     * @return
     */
    public static int randomIndex(List<T> list, Function<T, Integer> function);

    /**
     * 按照一个集合里面元素的权重随机。
     *
     * @param <T>
     * @param list
     * @param function
     * @return
     */
    public static T randomElement(List<T> list, Function<T, Integer> function);

    /**
     * 根据奖励的类别获取命中索引
     *
     * @param maxRandomNum
     * @param weight
     * @return
     */
    public static int randomIndex(int maxRandomNum, int[] weight);

    public static int randomIndex(List<Integer> weight);

    public static int randomIndex(float[] weight);

    public static int randomKey(List<Entry<Integer, Integer>> list);

    /**
     * 从带权重的对象集合里随机一个下标
     *
     * @param list
     * @return
     */
    public static int randomWeighableIndex(List<? extends Weightable> list);

    /**
     * 从带权重的对象集合里随机一个下标，排除指定索引的元素
     *
     * @param excludeIndexs 排除的索引
     * @param list
     * @return
     */
    public static int randomWeighableIndexExcludeIndex(List<? extends Weightable> list, List<Integer> excludeIndexs);

    /**
     * 从带权重的对象集合里随机一个下标，排除指定索引的元素
     *
     * @param excludeIndexs 排除的索引
     * @param list
     * @return
     */
    public static int randomIndexExcludeIndex(List<T> list, Function<T, Integer> function, List<Integer> excludeIndexs);

    /**
     * 从多个集合中，按权重随机出来一个元素
     *
     * @param list
     * @return
     */
    public static T randomWeighableElementFromMultipleList(List<T>... list);

    /**
     * 按照权重随机出来一个元素
     *
     * @param <T>
     * @param list
     * @return
     */
    public static T randomWeighableElement(List<T> list);

    /**
     * 按权重随机出指定数量的不重复的元素索引
     *
     * @param list
     * @param count
     * @return
     */
    public static List<Integer> randomWeighableIndexsNonRepeating(List<? extends Weightable> list, int count);

    public static List<Integer> randomIndexsNonRepeating(List<T> list, Function<T, Integer> function, int count);

    public static int[] getRandomNumbers(int[] array, int count);

    /**
     * 按权重随机出指定数量的不重复的元素索引
     *
     * @param list
     * @param count
     * @return
     */
    public static List<T> randomWeighableElementsNonRepeating(List<T> list, int count);

    /**
     * 按权重随机出指定数量的不重复的元素
     *
     * @param list
     * @param count
     * @return
     */
    public static List<T> randomElementsNonRepeating(List<T> list, Function<T, Integer> function, int count);

    /**
     * 索引在start和end之间，按权重随机出来一个
     *
     * @param weight
     * @param start
     * @param end 可能超过数组最大长度，则从0继续开始
     * @return
     */
    public static int random(int[] weight, int start, int end);

    /**
     * 索引在start和end之间，按权重随机出来一个
     *
     * @param weight
     * @param start
     * @param end 可能超过数组最大长度，则从0继续开始
     * @return
     */
    public static int random(List<Integer> weight, int start, int end);

    /**
     * 从一个指定集合中，随机出指定数量的元素
     *
     * @param list
     * @param count
     * @return
     */
    public static List<E> randomSubList(List<E> list, int count);

    /**
     * 从一个数组中，随机出指定数量的元素
     *
     * @param list
     * @param count
     * @return
     */
    public static List<Integer> randomSubList(int[] array, int count);

    /**
     * 从一个数组中，随机出指定数量的元素
     *
     * @param array
     * @param count
     * @return
     */
    public static int[] randomSubArray(int[] array, int count);

    /**
     * 一个权重集合，如果当前命中，则继续计算下一个，每命中一个 返回值 + 1
     *
     * @param weights
     * @return
     */
    public static int randomCount(float[] weights);

    /**
     * 万分比随机
     *
     * @param value
     * @return
     */
    public static boolean hit(int value);

    public static boolean hit(float value);

    /**
     * 按百分比随机
     *
     * @param value
     * @return
     */
    public static boolean hitPercentage(int value);

    /**
     * 包含两个数字的的数组，0为最小数，1为最大数，在范围中随机
     * 也允许数组中只有一个元素
     *
     * @param value
     * @return
     */
    public static int randomInRange(int[] value);

    public static T randomElement(List<T> list);

    public static T randomElement(T[] array);

    public static int randomInt(int[] array);

    public static T randomElement(Collection<T> collection);

    public static List<T> randomElements(Collection<T> collection, int k);

    /**
     * 从一个Set中随机出一个元素，并且这个元素不在排除的集合中
     *
     * @param sourceSet
     * @param excluded
     * @return
     */
    public static T randomElementExcluded(Set<T> sourceSet, Collection<T> excluded);

    /**
     * id;weight|id;weight
     * 按weight随机出来id
     *
     * @param array
     * @return
     */
    public static int randomId(int[][] array);

    /**
     * 生成指定范围内的N个不重复随机数
     *
     * @param start 起始值（包含）
     * @param end 结束值（包含）
     * @param n 需要生成的随机数个数
     * @return 包含N个不重复随机数的列表
     * @throws IllegalArgumentException 当参数不合法时抛出异常
     */
    public static List<Integer> generateRandomNumbers(int start, int end, int n);

    public static void main(String[] args);

}
```
