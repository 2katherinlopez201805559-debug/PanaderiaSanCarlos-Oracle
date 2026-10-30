package BACKEND.utils;

import com.itextpdf.io.image.ImageData;
import com.itextpdf.io.image.ImageDataFactory;
import com.itextpdf.kernel.font.PdfFont;
import com.itextpdf.kernel.geom.Rectangle;
import com.itextpdf.kernel.pdf.PdfDocument;
import com.itextpdf.kernel.pdf.PdfPage;
import com.itextpdf.kernel.pdf.PdfReader;
import com.itextpdf.kernel.pdf.PdfWriter;
import com.itextpdf.kernel.pdf.StampingProperties;
import com.itextpdf.layout.Document;
import com.itextpdf.layout.Style;
import com.itextpdf.layout.element.Image;
import com.itextpdf.signatures.BouncyCastleDigest;
import com.itextpdf.signatures.DigestAlgorithms;
import com.itextpdf.signatures.IExternalDigest;
import com.itextpdf.signatures.IExternalSignature;
import com.itextpdf.signatures.PdfSignatureAppearance;
import com.itextpdf.signatures.PdfSigner;
import com.itextpdf.signatures.PdfSigner.CryptoStandard;
import com.itextpdf.signatures.PrivateKeySignature;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Security;
import java.security.cert.Certificate;
import org.bouncycastle.cert.X509CertificateHolder;
import static oracle.jdbc.replay.OracleDataSource.PASSWORD;
import java.util.Date;
import BACKEND.utils.ResourceLoader;
import org.apache.commons.codec.binary.Base64;

import org.bouncycastle.jce.provider.BouncyCastleProvider;

public class FirmarDocumento {
    
	public String SRC="";
	public String DEST="";
	public String PASSWORD="0rg@n1sm0GT";
        
   public FirmarDocumento(String SRC,String DEST) throws IOException
   {
    this.SRC=SRC;
    this.DEST=DEST;
    };

    
    public  String FirmarToBase64() throws IOException, GeneralSecurityException        
    {
        String Salida;
        try
        {
            
        BouncyCastleProvider provider = new BouncyCastleProvider();
	Security.addProvider(provider);
	ResourceLoader resLogo=new ResourceLoader("logoOJ.png");
        ResourceLoader resCertif=new ResourceLoader("ncoj.pfx");
        KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
        ks.load(resCertif.getResource(), PASSWORD.toCharArray());
    
	String alias = (String)ks.aliases().nextElement();
        PrivateKey key = (PrivateKey)ks.getKey(alias, PASSWORD.toCharArray());
        java.security.cert.Certificate[] chain = ks.getCertificateChain(alias);
      
        PdfReader reader = new PdfReader(SRC);
 	PdfDocument pdfDoc = new PdfDocument(reader);
 	PdfPage page=pdfDoc.getLastPage();
 	Rectangle pg=page.getPageSize();
 	
        PdfSigner signer = new PdfSigner(reader, new FileOutputStream(DEST), false);
        // Creando el diseño de la firma
        PdfSignatureAppearance appearance = signer.getSignatureAppearance()
                .setReason("Portal de Servicios Electronicos del Organismo Judicial")
                .setLocation("http://www.oj.gob.gt")
                .setReuseAppearance(false)
                .setRenderingMode(PdfSignatureAppearance.RenderingMode.GRAPHIC_AND_DESCRIPTION)
                .setSignatureGraphic(ImageDataFactory.create(resLogo.getResourcePath()));
        //Rectangle rect = new Rectangle(400, 75,150, 75);
        Rectangle rect = new Rectangle(400, 75,150, 75);
        appearance.setPageRect(rect).setPageNumber(pdfDoc.getNumberOfPages());
        signer.setFieldName("sig");
        
        // Creadon la Firma con la Clave Interna
        IExternalSignature pks = new PrivateKeySignature(key, DigestAlgorithms.SHA256, provider.getName());
        IExternalDigest digest = new BouncyCastleDigest();
        signer.setCertificationLevel(PdfSigner.CERTIFIED_NO_CHANGES_ALLOWED);
        signer.signDetached(digest, pks, chain, null, null, null, 0, CryptoStandard.CMS);
        pdfDoc.close();
        
          File archivo = new File(DEST);
        FileInputStream fileInputStreamReader = new FileInputStream(archivo);
            byte[] bytes = new byte[(int)archivo.length()];
            fileInputStreamReader.read(bytes);
            Salida = new String(Base64.encodeBase64(bytes));
            
            
       
                }
       catch (Exception e) 
        {
	Salida=e.getMessage();
  
         } 
                
        return Salida;
    }
    
    public  String Firmar() throws IOException, GeneralSecurityException        
    {
        String Salida;
        try
        {
            
        BouncyCastleProvider provider = new BouncyCastleProvider();
	Security.addProvider(provider);
	ResourceLoader resLogo=new ResourceLoader("logoOJ.png");
        ResourceLoader resCertif=new ResourceLoader("ncoj.pfx");
        KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
        ks.load(resCertif.getResource(), PASSWORD.toCharArray());
    
	String alias = (String)ks.aliases().nextElement();
        PrivateKey key = (PrivateKey)ks.getKey(alias, PASSWORD.toCharArray());
        java.security.cert.Certificate[] chain = ks.getCertificateChain(alias);
      
        PdfReader reader = new PdfReader(SRC);
 	PdfDocument pdfDoc = new PdfDocument(reader);
 	PdfPage page=pdfDoc.getLastPage();
 	Rectangle pg=page.getPageSize();
 	
        PdfSigner signer = new PdfSigner(reader, new FileOutputStream(DEST), false);
        // Creando el diseño de la firma
        PdfSignatureAppearance appearance = signer.getSignatureAppearance()
                .setReason("Portal de Servicios Electronicos del Organismo Judicial")
                .setLocation("http://www.oj.gob.gt")
                .setReuseAppearance(false)
                .setRenderingMode(PdfSignatureAppearance.RenderingMode.GRAPHIC_AND_DESCRIPTION)
                .setSignatureGraphic(ImageDataFactory.create(resLogo.getResourcePath()));
        //Rectangle rect = new Rectangle(400, 75,150, 75);
        Rectangle rect = new Rectangle(400, 75,150, 75);
        appearance.setPageRect(rect).setPageNumber(pdfDoc.getNumberOfPages());
        signer.setFieldName("sig");
        
        // Creadon la Firma con la Clave Interna
        IExternalSignature pks = new PrivateKeySignature(key, DigestAlgorithms.SHA256, provider.getName());
        IExternalDigest digest = new BouncyCastleDigest();
        signer.setCertificationLevel(PdfSigner.CERTIFIED_NO_CHANGES_ALLOWED);
        signer.signDetached(digest, pks, chain, null, null, null, 0, CryptoStandard.CMS);
        pdfDoc.close();        
        
            Salida = DEST;          
       
         }
       catch (Exception e) 
        {
	Salida=e.getMessage();
  
         } 
                
        return Salida;
    }
}
