/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

package uk.co.lutraconsulting;

import org.qtproject.qt.android.bindings.QtActivity;

import java.lang.Exception;

import android.util.Log;
import android.os.Bundle;
import android.os.Build;
import android.os.VibratorManager;
import android.os.Vibrator;
import android.os.VibrationEffect;
import android.os.VibrationAttributes;
import android.view.Display;
import android.view.Surface;
import android.view.View;
import android.view.DisplayCutout;
import android.view.Window;
import android.view.WindowManager;
import android.view.WindowInsets;
import android.view.WindowInsets.Type;
import android.view.WindowInsetsController;
import android.graphics.Insets;
import android.graphics.Color;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.content.ActivityNotFoundException;
import android.provider.DocumentsContract;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.FileNotFoundException;
import androidx.core.content.FileProvider;
import android.widget.Toast;
import android.database.Cursor;
import android.provider.OpenableColumns;

import androidx.core.view.WindowCompat;
import androidx.core.splashscreen.SplashScreen;

public class MMActivity extends QtActivity
{
  private static final String TAG = "Mergin Maps Activity";
  private static final int MEDIA_CODE = 101;
  private boolean keepSplashScreenVisible = true;
  private String localTargetPath = null;
  private String imageCode = null;

  // Path of a .qgz file copied to the app cache by onNewIntent / onResume.
  // C++ reads and clears this via getAndConsumeExternalProjectPath().
  private static volatile String sPendingExternalProjectPath = null;

  // Track whether the launch / new intent has already been processed so
  // onResume does not handle the same intent a second time.
  private boolean mIntentHandled = false;

  // ── Extensions of layer files that may live alongside a .qgz project ───
  private static final String[] SIBLING_EXTENSIONS = {
    ".gpkg", ".shp", ".shx", ".dbf", ".prj", ".cpg", ".qmd", ".tif",
    ".geojson", ".json", ".kml", ".kmz", ".sqlite", ".db"
  };

  @Override
  public void onCreate(Bundle savedInstanceState)
  {
    SplashScreen splashScreen = SplashScreen.installSplashScreen( this );
    super.onCreate(savedInstanceState);
    
    // this is to keep the screen on all the time so the device does not
    // go into sleep and recording is not interrupted
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

    splashScreen.setKeepOnScreenCondition( () -> keepSplashScreenVisible );

    setCustomStatusAndNavBar();
  }

  @Override
  protected void onNewIntent( Intent intent ) {
    super.onNewIntent( intent );
    // Update getIntent() so that onResume sees the latest intent
    setIntent( intent );
    mIntentHandled = false;
    handleViewIntent( intent );
    mIntentHandled = true;
  }

  @Override
  protected void onResume() {
    super.onResume();
    if ( !mIntentHandled ) {
      Intent intent = getIntent();
      if ( intent != null ) {
        handleViewIntent( intent );
      }
      mIntentHandled = true;
    }
  }

  /**
   * Handles ACTION_VIEW intents that carry a .qgz file URI.
   * Copies the file (and best-effort sibling layer files) to the app cache
   * and stores the resulting POSIX path so C++ can retrieve it.
   */
  private void handleViewIntent( Intent intent ) {
    if ( intent == null ) return;
    if ( !Intent.ACTION_VIEW.equals( intent.getAction() ) ) return;

    Uri data = intent.getData();
    if ( data == null ) return;

    String fileName = getFileName( data );
    if ( fileName == null || !fileName.toLowerCase().endsWith( ".qgz" ) ) return;

    // Use a dedicated sub-directory inside the cache so project files are
    // grouped and can be cleaned up together.
    File cacheDir = new File( getCacheDir(), "external_projects" );
    if ( !cacheDir.exists() ) {
      cacheDir.mkdirs();
    }

    String cacheDirPath = cacheDir.getAbsolutePath();
    String resultPath = importQgzFile( data, cacheDirPath );

    if ( resultPath == null || resultPath.isEmpty() ) {
      Log.e( TAG, "handleViewIntent – importQgzFile failed for URI: " + data );
      return;
    }

    // Strip the file:// prefix if present
    if ( resultPath.startsWith( "file://" ) ) {
      resultPath = Uri.parse( resultPath ).getPath();
    }

    // Best-effort: also copy layer files that share the same base name
    String baseName = fileName.substring( 0, fileName.lastIndexOf( '.' ) );
    trySiblingFiles( data, baseName, cacheDirPath );

    Log.d( TAG, "handleViewIntent – external project ready at: " + resultPath );
    sPendingExternalProjectPath = resultPath;
  }

  /**
   * Returns the POSIX path of the last externally opened .qgz file and then
   * clears it so the same path is not returned again on subsequent calls.
   *
   * Called from C++ via JNI in FilePickerManager::checkPendingExternalProject().
   */
  public static String getAndConsumeExternalProjectPath() {
    String path = sPendingExternalProjectPath;
    sPendingExternalProjectPath = null;
    return path != null ? path : "";
  }

  /**
   * Attempts to copy layer files that share the same base name as the opened
   * .qgz project (e.g. parcelas.gpkg, parcelas.shp …) to the cache directory.
   *
   * Works for DocumentsProvider URIs (Files app, OTG storage …). Silently
   * skips the step for providers that do not support child-document queries.
   *
   * @param qgzUri   The content:// URI of the .qgz file.
   * @param baseName Base name without extension (lower-cased for comparison).
   * @param cacheDir Absolute path of the destination directory.
   */
  private void trySiblingFiles( Uri qgzUri, String baseName, String cacheDir ) {
    if ( !"content".equals( qgzUri.getScheme() ) ) return;

    try {
      // Retrieve the raw document ID carried in the URI
      String rawDocId = DocumentsContract.getDocumentId( qgzUri );
      if ( rawDocId == null ) return;

      // Derive the parent document ID by stripping the filename segment
      int lastSlash = rawDocId.lastIndexOf( ':' );
      if ( lastSlash < 0 ) lastSlash = rawDocId.lastIndexOf( '/' );
      if ( lastSlash < 0 ) return;

      String parentId = rawDocId.substring( 0, lastSlash );

      // Build a tree URI for the parent; this is the URI we query for children
      Uri treeRoot = DocumentsContract.buildTreeDocumentUri(
          qgzUri.getAuthority(), parentId );
      Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
          treeRoot, parentId );

      Cursor c = getContentResolver().query(
          childrenUri,
          new String[] {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME
          },
          null, null, null );

      if ( c == null ) return;

      try {
        while ( c.moveToNext() ) {
          String displayName = c.getString( 1 );
          if ( displayName == null ) continue;

          int dotIdx = displayName.lastIndexOf( '.' );
          String siblingBase = ( dotIdx > 0
              ? displayName.substring( 0, dotIdx )
              : displayName ).toLowerCase();
          String siblingExt = dotIdx > 0
              ? displayName.substring( dotIdx ).toLowerCase()
              : "";

          if ( !siblingBase.equals( baseName.toLowerCase() ) ) continue;

          boolean isTarget = false;
          for ( String ext : SIBLING_EXTENSIONS ) {
            if ( ext.equals( siblingExt ) ) {
              isTarget = true;
              break;
            }
          }
          if ( !isTarget ) continue;

          String siblingDocId = c.getString( 0 );
          Uri siblingUri = DocumentsContract.buildDocumentUriUsingTree(
              treeRoot, siblingDocId );

          File dest = new File( cacheDir, displayName );
          try {
            InputStream is = getContentResolver().openInputStream( siblingUri );
            if ( is == null ) continue;
            if ( dest.exists() ) dest.delete();
            dest.createNewFile();
            copyFile( is, dest );
            Log.d( TAG, "trySiblingFiles – copied: " + displayName );
          } catch ( IOException | SecurityException e ) {
            Log.w( TAG, "trySiblingFiles – skipping " + displayName
                + ": " + e.getMessage() );
          }
        }
      } finally {
        c.close();
      }

    } catch ( IllegalArgumentException | UnsupportedOperationException e ) {
      // Not a DocumentsProvider URI – silently ignore
      Log.d( TAG, "trySiblingFiles – not a documents URI, skipping: "
          + e.getMessage() );
    }
  }

/**
 * Copies a .qgz file selected via SAF (content:// URI) to the app's
 * private cache directory and returns its absolute path as a file:// URI
 * string.  Returns an empty string on failure.
 *
 * Called from C++ via JNI in FilePickerManager::handleActivityResult().
 *
 * @param qgzUri     The content:// URI delivered by ACTION_OPEN_DOCUMENT.
 * @param cacheDir   Absolute path to the target directory
 *                   (QStandardPaths::CacheLocation on the C++ side).
 */
public String importQgzFile( Uri qgzUri, String cacheDir ) {

  // Resolve the display name so we preserve the original filename
  String fileName = getFileName( qgzUri );

  // Guarantee the file ends with .qgz so QGIS recognises it
  if ( fileName == null || fileName.isEmpty() ) {
    fileName = "imported_project.qgz";
  }
  if ( !fileName.toLowerCase().endsWith( ".qgz" ) ) {
    fileName = fileName + ".qgz";
  }

  // Make sure the destination directory exists
  File destDir = new File( cacheDir );
  if ( !destDir.exists() ) {
    destDir.mkdirs();
  }

  File destFile = new File( destDir, fileName );

  try {
    // Delete any previous copy with the same name to keep cache clean
    if ( destFile.exists() ) {
      destFile.delete();
    }
    destFile.createNewFile();

    InputStream src = getContentResolver().openInputStream( qgzUri );
    copyFile( src, destFile );   // reuses the existing copyFile() helper

    // Return a file:// URI string – C++ strips the prefix if needed
    return Uri.fromFile( destFile ).toString();

  } catch ( IOException e ) {
    Log.e( TAG, "importQgzFile – IOException: " + e.getMessage() );
    return "";
  } catch ( SecurityException e ) {
    Log.e( TAG, "importQgzFile – SecurityException (URI permission gone?): "
                + e.getMessage() );
    return "";
  }
}

  public String homePath()
  {
    return getFilesDir().getAbsolutePath();
  }

  void setCustomStatusAndNavBar() 
  {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
      Log.d( TAG, "Unsupported Android version for painting behind system bars." );
      return;
    } 
    else {
      WindowCompat.setDecorFitsSystemWindows(getWindow(), false);

      Window window = getWindow();

      // on Android 15+ all apps are edge-to-edge
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
        // draw app edge-to-edge
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);

        // make the status bar background color transparent
        window.setStatusBarColor(Color.TRANSPARENT);

        // make the navigation button background color transparent
        window.setNavigationBarColor(Color.TRANSPARENT);
      }

      // do not show background dim for the navigation buttons
      window.setNavigationBarContrastEnforced(false); 

      // change the status bar text color to black
      WindowInsetsController insetsController = window.getDecorView().getWindowInsetsController();
    
      if (insetsController != null) {
          insetsController.setSystemBarsAppearance(WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS);
      }
    }
  }

  public String getSafeArea() {

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
      Log.d( TAG, "Unsupported Android version for painting behind system bars." );
      return ( "0,0,0,0" );
    }
    else {
      WindowInsets windowInsets = getWindow().getDecorView().getRootWindowInsets();

      if ( windowInsets == null ) {
        Log.d( TAG, "Try to ask for insets later" );
        return null;
      }

      Insets safeArea = windowInsets.getInsets( android.view.WindowInsets.Type.statusBars() | 
                                                android.view.WindowInsets.Type.navigationBars() | 
                                                android.view.WindowInsets.Type.displayCutout() );
                                                
      return ( "" + safeArea.top + "," + safeArea.right + "," + safeArea.bottom + "," + safeArea.left );
    }
  }

  public String getManufacturer() {
    return android.os.Build.MANUFACTURER.toUpperCase();
  }

  public String getDeviceModel() {
      return android.os.Build.MODEL.toUpperCase();
  }

  public void hideSplashScreen()
  {
    keepSplashScreenVisible = false;
  }

  public boolean openFile( String filePath ) {
    File file = new File( filePath );

    if ( !file.exists() ) 
    {
        return false;
    }

    Intent showFileIntent = new Intent( Intent.ACTION_VIEW );

    try 
    {
      Uri fileUri = FileProvider.getUriForFile( this, "uk.co.lutraconsulting.fileprovider", file );

      showFileIntent.setData( fileUri );

      // FLAG_GRANT_READ_URI_PERMISSION grants temporary read permission to the content URI.
      // FLAG_ACTIVITY_NEW_TASK is used when starting an Activity from a non-Activity context.
      showFileIntent.setFlags( Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION );
    } 
    catch ( IllegalArgumentException e )
    {
      return false;
    }

    if ( showFileIntent.resolveActivity( getPackageManager() ) != null ) 
    {
      startActivity( showFileIntent );
    } 
    else 
    {
      return false;
    }
    
    return true;
  }

  public String importImage(Uri imageUri, String targetPath) {
    String fileName = getFileName( imageUri );
    File newCopyFile = new File( targetPath + "/" + fileName );
    try {
      newCopyFile.createNewFile();
      InputStream fileStream = getContentResolver().openInputStream( imageUri );
      copyFile( fileStream, newCopyFile );
      return Uri.fromFile( newCopyFile ).toString();
    } catch (IOException e) {
      Log.e( TAG, "IOException while importing image from gallery!" );
      return "";
    }
  }

  public void copyFile(InputStream src, File dst) throws IOException {
    OutputStream out = null;

    try {
      out = new FileOutputStream(dst);
      // Transfer bytes from src to out
      byte[] buf = new byte[1024];
      int len;
      while ((len = src.read(buf)) > 0) {
        out.write(buf, 0, len);
      }
    } catch (IOException e) {
      throw new IOException("Cannot copy a photo to working directory.");
    } finally {
      if (src != null)
        src.close();
      if (out != null)
        out.close();
    }
  }

  public String getFileName(Uri uri) {
    String result = null;
    // try to get the file name from DISPLAY_NAME column in URI data
    if (uri.getScheme().equals("content")) {
      Cursor cursor = getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null);
      try {
        if (cursor != null && cursor.moveToFirst()) {
          result = cursor.getString(0);
        }
      } finally {
        cursor.close();
      }
    }
    // if the previous approach fails just grab the name from URI, the last segment is the file name without suffix
    if (result == null) {
      result = uri.getPath();
      int cut = result.lastIndexOf('/');
      if (cut != -1) {
        result = result.substring(cut + 1);
      }
    }
    return result;
  }

  public void quitGracefully()
  {
    String man = android.os.Build.MANUFACTURER.toUpperCase();

    Log.d( TAG, String.format("quitGracefully() from Java, MANUFACTURER: '%s'", man ) );
    
    //
    // QT app exit on back button causes crashes on some manufacturers (mainly Huawei, but also Samsung Galaxy recently).
    //
    // Let's play safe and only use this fix for HUAWEI phones for now.
    // If the fix proves itself in next release, we can add it for all other manufacturers.
    //
    // Qt bug: QTBUG-82617
    // See: https://developernote.com/2022/03/crash-at-std-thread-and-std-mutex-destructors-on-android/#comment-694101
    // See: https://stackoverflow.com/questions/61321845/qt-app-crashes-at-the-destructor-of-stdthread-on-android-10-devices
    //

    boolean shouldQuit = man.contains( "HUAWEI" );

    if ( shouldQuit )
    {
      try
      {
        finishAffinity();
        System.exit(0);
      }
      catch ( Exception exp )
      {
        exp.printStackTrace();
        Log.d( TAG, String.format( "quitGracefully() failed to execute: '%s'", exp.toString() ) );
      }
    }
  }

  public void vibrate()
  {
    Vibrator vib;
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S)
    {
      vib = (Vibrator) getSystemService(getApplicationContext().VIBRATOR_SERVICE);
    } else
    {
      VibratorManager vibManager = (VibratorManager) getSystemService(getApplicationContext().VIBRATOR_MANAGER_SERVICE);
      vib = vibManager.getDefaultVibrator();
    }

    // The reason why we use duplicate calls to vibrate is because some manufacturers (samsung) don't support
    // the usage of predefined VibrationEffect and vice versa. In the end only one vibration gets executed.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU)
    {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
      {
        vib.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE));
      } else
      {
        vib.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK));
        vib.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE));
      }
    } else
    {
      vib.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK),
        VibrationAttributes.createForUsage(VibrationAttributes.USAGE_CLASS_FEEDBACK));
      vib.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE));
    }
  }

  @Override
  protected void onDestroy()
  {
    super.onDestroy();
  }
}
