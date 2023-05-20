# CS682
# Java Interoperability Unit Tests

Java interoperability unit tests between a java client and dart client. The problem focuses on testing the consistency of communication between server and two different clients. We explore sending and retrieving of same key-value pair between a java and dart client.

## Setting up the project:

### Requirements:

•	[Java editor](https://www.jetbrains.com/idea/download/#section=mac)

•	[Flutter SDK](https://docs.flutter.dev/get-started/install/macos)


Initially we create an atSign by navigating to [Link](https://my.atsign.com/choose-atsign/a4a9686d92be5d97259bda204585a90ebbe09363fa3708612aefbd6a9cd9c770)
  and place the downloaded keys in a seperate keys folder in your project.

#### For Java client:
•	Pull the at_java repository from [Link](https://github.com/atsign-foundation/at_java.git) into your local machine with an IDE installed such as       Eclipse/Visual Studio Code.  

•	Install Maven dependencies by running the pom.xml file provided in the pulled repository.


#### For Dart client:
•	Pull the at_client_sdk repository from [Link](https://github.com/atsign-foundation/at_client_sdk.git) into your local machine with an IDE installed   such as Eclipse/Visual Studio Code.  

•	Install dependencies by running the pubspec.yaml file present in at_client_sdk>tests.

## Running the Project:
Sending keys from:  

   1.	Dart client to Java client:  
   
    a.	Open terminal/command line in Mac/Windows.  
    
    b.	Type ./dartToJava.sh to run the script to send keys from dart client to java client.  
    
    c.	The terminal should display the sent and received keys and namespace.
    
   2.	Java client to Dart client:  
   
    a.	Open terminal/command line in Mac/Windows.  
    
    b.	Type ./javaToDart.sh to run the script to send keys from dart client to java client.  
    
    c.	The terminal should display the sent and received keys and namespace.
  

   


