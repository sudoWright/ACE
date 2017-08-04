using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using System;
using System.IO;
using System.Threading;
using System.Net.Http;
using System.Text;
using System.Linq;
using VirusTotalNET;
using VirusTotalNET.Results;
using VirusTotalNET.Exceptions;

namespace ACE_RabbitMQ
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Length != 4)
            {
                Console.WriteLine("Invalid arguments, please enter:");
                Console.WriteLine(@"    ace-rabbitmq.exe [server] [username] [password] [virustotal_apikey]");
                return;
            }
            var factory = new ConnectionFactory()
            {
                HostName = args[0],
                UserName = args[1],
                Password = args[2]
            };
            VirusTotal virusTotal = new VirusTotal(args[3]);
            virusTotal.UseTLS = true;
            using (var connection = factory.CreateConnection())
            using (var channel = connection.CreateModel())
            {
                //Topic exchange for routing all ACE traffic to correct queues
                channel.ExchangeDeclare(exchange: "ace_exchange", type: "topic");
                //Queue for writing to file
                channel.QueueDeclare(queue: "file_output",
                                         durable: false,
                                         exclusive: false,
                                         autoDelete: false,
                                         arguments: null);
                //Queue for writing to SIEM
                channel.QueueDeclare(queue: "siem",
                                         durable: false,
                                         exclusive: false,
                                         autoDelete: false,
                                         arguments: null);
                //Queue for enriching with VT hash results
                channel.QueueDeclare(queue: "pre_hash",
                                         durable: false,
                                         exclusive: false,
                                         autoDelete: false,
                                         arguments: null);

                //Binding keys to queues for all current entries
                channel.QueueBind(queue: "file_output",
                                  exchange: "ace_exchange",
                                  routingKey: "file");
                channel.QueueBind(queue: "siem",
                                      exchange: "ace_exchange",
                                      routingKey: "siem");
                channel.QueueBind(queue: "pre_hash",
                                      exchange: "ace_exchange",
                                      routingKey: "hash.#");
                
                //Optional debug that script is running
                Console.WriteLine(" [*] Waiting for messages.");
                //Create VT Hash lookup consumer
                EventingBasicConsumer hashlookupconsumer = new EventingBasicConsumer(channel);
                hashlookupconsumer.Received += (model, ea) =>
                {
                    Console.WriteLine("Creating Hash Consumer");
                    var body = ea.Body;
                    var message = Encoding.UTF8.GetString(body);
                    var routingKey = ea.RoutingKey;

                    // Get Hash 
                    try
                    {
                        //Console.WriteLine("Parsing JSON");
                        JObject originalMessage = JObject.Parse(message);
                        string hash = (string)originalMessage["SHA256Hash"];
                        Console.WriteLine(" [+] Looking up Hash: {0}", hash);

                        // Do Lookup 
                        FileReport vtreport = virusTotal.GetFileReport(hash).Result;
                        if (vtreport.ResponseCode.ToString() == "Present")
                        {
                            originalMessage.Add("VTRecordExists", "True");
                            originalMessage.Add("VTPositives", vtreport.Positives.ToString());
                        }
                        else
                        {
                            originalMessage.Add("VTRecordExists", "False");
                        }

                        string enrichedMessage = originalMessage.ToString(Newtonsoft.Json.Formatting.None);

                        body = Encoding.UTF8.GetBytes(enrichedMessage);
                    }
                    catch (AggregateException)
                    {
                        Console.WriteLine("Rate Limit Exception - Sleeping 1 minute");
                        Thread.Sleep(60000);
                        JObject originalMessage = JObject.Parse(message);
                        string hash = (string)originalMessage["SHA256Hash"];
                        Console.WriteLine(" [+] Looking up Hash: {0}", hash);

                        // Do Lookup 
                        FileReport vtreport = virusTotal.GetFileReport(hash).Result;
                        if (vtreport.ResponseCode.ToString() == "Present")
                        {
                            originalMessage.Add("VTRecordExists", "True");
                            originalMessage.Add("VTPositives", vtreport.Positives.ToString());
                        }
                        else
                        {
                            originalMessage.Add("VTRecordExists", "False");
                        }

                        string enrichedMessage = originalMessage.ToString(Newtonsoft.Json.Formatting.None);

                        body = Encoding.UTF8.GetBytes(enrichedMessage);
                        
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine("General Exception" + e);
                    }

                    // parse "hash." off front of routing key
                    string[] words = routingKey.Split('.');
                    words = words.Skip(1).ToArray();
                    routingKey = string.Join(".", words);

                    //Ack recieving the message from the queue
                    channel.BasicAck(deliveryTag: ea.DeliveryTag, multiple: false);
                    //Publish new enriched message back to ACE exchange for routing
                    channel.BasicPublish(exchange: "ace_exchange",
                                         routingKey: routingKey,
                                         basicProperties: null,
                                         body: body);
                };
                //Implement an instance of the VT hashing consumer, can create multiple to distribute load as required
                channel.BasicConsume(queue: "pre_hash",
                                    noAck: false,
                                    consumer: hashlookupconsumer);
                
                //File writer consumer
                EventingBasicConsumer filewriterconsumer = new EventingBasicConsumer(channel);
                filewriterconsumer.Received += (model, ea) =>
                {
                    var body = ea.Body;
                    var message = Encoding.UTF8.GetString(body);
                    var routingKey = ea.RoutingKey;

                    JObject data = JObject.Parse(message);

                    DateTime scanDate = DateTime.Parse(data["ResultDate"].ToString());

                    // Result file: DIGSStorageDirectory\SCAN_ID\RESULT_ID\SCANTYPE_DATE_COMPUTER_SCANGUID.json
                    string resultsDir = @"C:\test\scans" + Path.DirectorySeparatorChar + data["scanId"] + Path.DirectorySeparatorChar + data["ResultId"];
                    string resultsFileName = data["scanType"] + "_" + scanDate.ToString("yyyyMMddThhmmssmsmsZ") + "_" + data["ComputerName"] + "_" + data["ResultId"] + ".json";
                    string resultsFile = resultsDir + Path.DirectorySeparatorChar + Path.GetFileName(resultsFileName);  // Prevent directory traversal

                    if (!Directory.Exists(resultsDir))
                    {
                        Directory.CreateDirectory(resultsDir);
                    }

                    if (File.Exists(resultsFile))
                    {
                        //throw new Exception("Results file already exists. Results file path: " + resultsFile);
                    }
                    else
                    {
                        Console.WriteLine(" [*] Writing data to {0}.", resultsFile);
                        File.WriteAllText(resultsFile, data["Data"].ToString(Formatting.None), Encoding.UTF8);
                        Console.WriteLine(" [+] Done writing data to {0}.", resultsFile);
                    }

                    channel.BasicAck(deliveryTag: ea.DeliveryTag, multiple: false);
                };
                //Implement an instance of the File Writing consumer, can create multiple to distribute load as required
                channel.BasicConsume(queue: "file_output",
                                    noAck: false,
                                    consumer: filewriterconsumer);

                Console.WriteLine(" Press [enter] to exit.");
                Console.ReadLine();
            }
        }
    }
}
