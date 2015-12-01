<?php
/*
 
	C8XMQLib 0.1b
	
	boolean set_xmq_type({'unix' or 'tcp'}) // connection type
	boolean set_xmq_connection_timeout({int seconds}) // connection timeout
	boolean add_message({uri string}, {post data string}) // add message to queue
	array run() //send messages

	example:
	
	<?php
		include_once 'lib/c8httplib.class.php';
		include_once 'lib/c8xmq.class.php';
		
		
		$xmq = new C8XMQLib();
		
		$xmq->set_xmq_type('unix');	
		$xmq->set_xmq_connection_timeout(10); 
		$xmq->add_message('/send/?dst=gw.c8.net.ua/agrregate.php', '{dkled:1}');
		$xmq->run();
	?>
	
	@Stas Oreshin <stas@c8.net.ua>
*/


class C8XMQLib {

  private $conn_timeout_ms = 1000;
  private $http_array = array();
  private $xmq_dst = '';

  //init constructor
  //function __construct($arg = null)
  //{
  //
  //}

  function set_xmq_type($mode = 'unix')
  {
	if($mode != 'unix')
	{
		$this->xmq_dst = 'tcp://127.0.0.1:55';
	}
	else
	{
		$this->xmq_dst = 'unix:///var/run/nginx_mq.sock';
	}
	return true;
  }
  
  function set_xmq_connection_timeout($timeout)
  {
	if(!$timeout || !is_numeric($timeout) || $timeout<1)
		return false;
	$this->conn_timeout_ms = (int)$timeout;
	return true;
  }
  
  function add_message($dst_uri = '/index.php', $post_data)
  {
	$http_array	= array();
	$host		= array();
	$host['host'] 	= $this->xmq_dst;
	$host['uri'] 	= $dst_uri;

	$host['hostname'] 	= '127.0.0.1';
	$host['content_type'] 	= 'application/json';
	$host['post_data'] 	= $post_data;
	$host['headers'] 	= array("x-xmq-version: 0.1b");
	$this->http_array[]	= $host;
	
	return true;
        //thronew C8XMQLibException("Argument 2 is expected to be a callable, " . gettype($arg2) . " given");

  }
  function run()
  {
	return $this->_process_message();
  }
  
  /* Starting private methods */
  private function _process_message()
  {

	  $ps = new C8HttpLib();

	  $ps->http_post_multi($this->http_array);

	  $ps->settimeout(1000);

	  try{

		  if($ps->run())
		  {

			  $http_responses=$ps->getresponse();


			  foreach($http_responses as $_id=>$resp){
				  $response[$_id]=$resp;

			  }


			  return $response;

		  }else{

			  return false;
		  }



	  }catch(Exception $e){

		  return false;
	  }
  }


}

class C8XMQException extends RuntimeException {}
