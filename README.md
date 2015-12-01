# xmq
Реализация демона асинхронной очереди на базе nginx+lua + PHP класс-коннектор<br />
<br />
Пример использования:<br />
<br /><br />
	<?php<br />
		include_once 'c8httplib.class.php';<br />
		include_once 'c8xmq.class.php';<br />
		<br />
		<br />
		$xmq = new C8XMQLib();<br />
		<br />
		$xmq->set_xmq_type('unix');	<br />
		$xmq->set_xmq_connection_timeout(10); <br />
		$xmq->add_message('/send/?dst=dst.host.com/agrregate.php', '{msg:[1,2,3]}');<br />
		$xmq->run();<br />
	?><br /><br />