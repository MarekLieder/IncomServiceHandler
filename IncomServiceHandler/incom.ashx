<%@ WebHandler Language="C#" Debug="true" Class="incom" %>

using System;
using System.Collections.Generic;
using System.Web;
using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.ServiceModel;
using System.Xml;
using System.Xml.Serialization;
using System.IO;
using System.Text;
using IncomServiceHandler.Incom;

public class incom : IHttpHandler
{
    private readonly string myDocPath = @"c:\inetpub\log\ServiceLog."; //where and begining of file name
    private StreamWriter oFile;
    private readonly Boolean TurnLogOn = false; //to turn on and off logging
    private readonly Boolean UseAdresV2 = false; //to turn on and off of use of SetAdresWysyłkowyV2

    private void Log(string logText)
    {
        if (TurnLogOn)
            oFile.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm.ss.fff") + ": " + logText);
    }

    public incom()
    {
        if (TurnLogOn)
        {
            oFile = new StreamWriter(myDocPath + DateTime.Now.ToString("yyyy-MM-dd-HH-mm-ss-fff") + ".txt", true, Encoding.ASCII);
            oFile.AutoFlush = true;
        }
    }

    public void ProcessRequest(HttpContext context)
    {
        Log("begin of request");
        ServiceNetBaseClient client = new ServiceNetBaseClient("BasicBindingUserPassword_IServiceNetBase");
        Log("after new ServiceNetBaseClient | " + client.State.ToString());

        context.Response.ContentType = "text/xml";

        string username = context.Request.QueryString["user"];
        string password = context.Request.QueryString["pass"];

        Log("-- user:  " + username + " --pass: " + password);

        PermissiveCertificatePolicy.Enact("CN=*.incom.pl");
        Log("1) --> before opening a client | " + client.State.ToString());
        CreateLoginAndOpenService(client, username, password);
        Log("2) --> after opening a client | " + client.State.ToString());

        if (context.Request.QueryString["get"] == "invoices")
        {
            XmlSerializer s; TextWriter w; string filename;

            FakturyListType responseFakturyList;
            Log("before GetFakturyList | " + client.State.ToString());
            GetFakturyListRequest getFakturyListRequest = new GetFakturyListRequest();
            responseFakturyList = client.GetFakturyList(getFakturyListRequest).GetFakturyListResult;
            Log("after GetFakturyList | " + client.State.ToString());

            filename = Path.GetTempFileName();

            s = new XmlSerializer(typeof(FakturyListType));
            w = new StreamWriter(filename);
            s.Serialize(w, responseFakturyList);
            w.Close();

            StreamReader sr = new StreamReader(filename);
            context.Response.Write(sr.ReadToEnd());
        }
        if (context.Request.QueryString["get"] == "countries")
        {
            XmlSerializer s; TextWriter w; string filename;

            KrajeListType responseKrajeList;

            Log("before GetKrajeList | " + client.State.ToString());
            GetKrajeListRequest getKrajeListRequest = new GetKrajeListRequest();
            responseKrajeList = client.GetKrajeList(getKrajeListRequest).GetKrajeListResult;
            Log("after GetKrajeList | " + client.State.ToString());

            filename = Path.GetTempFileName();

            s = new XmlSerializer(typeof(KrajeListType));
            w = new StreamWriter(filename);
            s.Serialize(w, responseKrajeList);
            w.Close();

            StreamReader sr = new StreamReader(filename);
            context.Response.Write(sr.ReadToEnd());
        }
        else if (context.Request.QueryString["add"] == "order")
        {
            try
            {
                string OrderNr;

                var orderXML = new XmlDocument();
                //orderXML.LoadXml(context.Request.QueryString["xml"]);
                orderXML.LoadXml(context.Request.Form["xml"]);

                OrderNr = orderXML.SelectSingleNode("//OrderNr[1]").InnerText;

                string basketNr = Guid.NewGuid().ToString();

                KoszykType koszyk = new KoszykType();
                koszyk.Nazwa = basketNr;
                var list = new List<KoszykPozycjaType>();

                XmlNodeList orderLines = orderXML.SelectNodes("//l");

                foreach (XmlNode orderLine in orderLines)
                {
                    KoszykPozycjaType koszykPozycja = new KoszykPozycjaType();
                    koszykPozycja.Symbol = orderLine["p"].InnerText;
                    koszykPozycja.Ilość = Convert.ToDecimal(orderLine["q"].InnerText);

                    list.Add(koszykPozycja);
                }

                koszyk.KoszykPozycje = list.ToArray();
                Log("before SetKoszyk | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName);
                Log("basket details | " + koszyk.Nazwa + " | " + koszyk.KoszykPozycje.Length.ToString() + " | " + koszyk.KoszykPozycje.ToString());
                SetKoszykRequest setKoszykRequest = new SetKoszykRequest(koszyk);
                client.SetKoszyk(setKoszykRequest);
                Log("after SetKoszyk | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName);

                //context.Response.Write(orderXML.SelectSingleNode("//Company[1]").InnerText + " - " + orderXML.SelectSingleNode("//Contact[1]").InnerText + " - " +  orderXML.SelectSingleNode("//Street[1]").InnerText + " " + orderXML.SelectSingleNode("//Zip[1]").InnerText + " " + orderXML.SelectSingleNode("//City[1]").InnerText + " " + orderXML.SelectSingleNode("//Country[1]").InnerText);
                //context.Response.End();

                Guid addressID;
                Log("before SetAdresWysyłkowy | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName);

                if (UseAdresV2)
                {
                    SetAdresWysyłkowyV2Request setAdresWysyłkowyV2Request = new SetAdresWysyłkowyV2Request(
                        orderXML.SelectSingleNode("//Company[1]").InnerText,  //name for this address; for example: office, home, store no 3
                        orderXML.SelectSingleNode("//Company[1]").InnerText,
                        orderXML.SelectSingleNode("//City[1]").InnerText,
                        orderXML.SelectSingleNode("//Zip[1]").InnerText,
                        orderXML.SelectSingleNode("//Street[1]").InnerText,
                        orderXML.SelectSingleNode("//Country[1]").InnerText,
                        true,  //true for one time used addresses; false for addresses which can be used many times
                        orderXML.SelectSingleNode("//Note[1]").InnerText,
                        orderXML.SelectSingleNode("//Contact[1]").InnerText,
                        false,  //true when Incom should send invoice on this address; false when Incon mustn't send invoice on this address
                        orderXML.SelectSingleNode("//Phone[1]").InnerText, //phone number
                        orderXML.SelectSingleNode("//Email[1]").InnerText //email associated with this address
                    );
                    addressID = client.SetAdresWysyłkowyV2(setAdresWysyłkowyV2Request).SetAdresWysyłkowyV2Result;
                }
                else
                {
                    SetAdresWysyłkowyRequest setAdresWysyłkowyRequest = new SetAdresWysyłkowyRequest(
                        orderXML.SelectSingleNode("//Company[1]").InnerText,
                        orderXML.SelectSingleNode("//City[1]").InnerText,
                        orderXML.SelectSingleNode("//Zip[1]").InnerText,
                        orderXML.SelectSingleNode("//Street[1]").InnerText,
                        orderXML.SelectSingleNode("//Country[1]").InnerText,
                        true,
                        orderXML.SelectSingleNode("//Note[1]").InnerText,
                        orderXML.SelectSingleNode("//Contact[1]").InnerText,
                        false
                    );
                    addressID = client.SetAdresWysyłkowy(setAdresWysyłkowyRequest).SetAdresWysyłkowyResult;
                }
                Log("after SetAdresWysyłkowy | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName);

                int response = 0;
                string responseText = "";

                Log("before SetZamówienieV2 | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName);
                SetZamówienieV2Request setZamówienieV2Request = new SetZamówienieV2Request(
                    basketNr,
                    OrderNr,
                    orderXML.SelectSingleNode("//Note[1]").InnerText + " " + orderXML.SelectSingleNode("//Contact[1]").InnerText,
                    Convert.ToBoolean(orderXML.SelectSingleNode("//PartDelivery[1]").InnerText), //part delivery
                    0,
                    45,
                    orderXML.SelectSingleNode("//PaymentTerm[1]").InnerText, //"1.Przelew", // payment term
                    orderXML.SelectSingleNode("//CarrierID[1]").InnerText,  //"1. Kurier SCH", // carrier ID
                    addressID); //addresss ID = markit office
                response = client.SetZamówienieV2(setZamówienieV2Request).SetZamówienieV2Result;
                Log("after SetZamówienieV2 | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName);

                switch (response)
                {
                    case 0: responseText = "ok"; break;
                    case 20: responseText = "exceeded credit"; break;
                    case 21: responseText = "no shopping"; break;
                    case 22: responseText = "improperly paid"; break;
                    case 23: responseText = "improperly receive"; break;
                }

                context.Response.Write("<Response Status=\"" + response + "\" Text = \"" + responseText + "\" AddressID = \"" + addressID.ToString() + "\" />");
            }
            catch (Exception ex)
            {
                Log("after Exception | " + client.State.ToString() + " | " + client.ClientCredentials.UserName.UserName + " | " + ex.Message);
                context.Response.Write("<Response Status=\"1\" Text = \"" + HttpUtility.HtmlEncode(ex.Message) + "\" />");
            }            
        }
        else if (context.Request.QueryString["get"] == "catalog")
        {
            context.Response.Write("ok");
        }
        if (client != null)
          client.Close();
    }

    public bool IsReusable
    {
        get {
            return false;
        }
    }

    private void CreateLoginAndOpenService(ServiceNetBaseClient client, string username, string password)
    {
        Log("inside CreateLoginAndOpenService | " + client.State.ToString() + " | " + username);
        if (client.State == CommunicationState.Closed)
        {
            Log("inside CreateLoginAndOpenService CommunicationState.Closed | " + client.State.ToString() + " | " + username);
            client = null;
            client = new ServiceNetBaseClient();
            Log("inside CreateLoginAndOpenService CommunicationState.Closed after create new service | " + client.State.ToString() + " | " + username);
        }
        if ((client.State == CommunicationState.Closed) || (client.State == CommunicationState.Created))
        {
            client.ClientCredentials.UserName.UserName = username;
            client.ClientCredentials.UserName.Password = password;

            PermissiveCertificatePolicy.Enact("CN=*.incom.pl");
            Log("inside CreateLoginAndOpenService CommunicationState.Closed or Created before open | " + client.State.ToString() + " | " + username);
            client.Open();
            Log("inside CreateLoginAndOpenService CommunicationState.Closed or Created after open| " + client.State.ToString() + " | " + username);
        }
    }

    class PermissiveCertificatePolicy
    {
        string subjectName;
        static PermissiveCertificatePolicy currentPolicy;
        PermissiveCertificatePolicy(string subjectName)
        {
            this.subjectName = subjectName;
            ServicePointManager.ServerCertificateValidationCallback +=
                new System.Net.Security.RemoteCertificateValidationCallback(RemoteCertValidate);
        }

        public static void Enact(string subjectName)
        {
            currentPolicy = new PermissiveCertificatePolicy(subjectName);
        }

        bool RemoteCertValidate(object sender, X509Certificate cert, X509Chain chain, System.Net.Security.SslPolicyErrors error)
        {
            return true;
        }
    }
}