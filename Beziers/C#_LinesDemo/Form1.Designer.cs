namespace Clipper_Lines_Demo
{
  partial class MainForm
  {
    /// <summary>
    /// Required designer variable.
    /// </summary>
    private System.ComponentModel.IContainer components = null;

    /// <summary>
    /// Clean up any resources being used.
    /// </summary>
    /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
    protected override void Dispose(bool disposing)
    {
      if (disposing && (components != null))
      {
        components.Dispose();
      }
      base.Dispose(disposing);
    }

    #region Windows Form Designer generated code

    /// <summary>
    /// Required method for Designer support - do not modify
    /// the contents of this method with the code editor.
    /// </summary>
    private void InitializeComponent()
    {
      this.statusStrip1 = new System.Windows.Forms.StatusStrip();
      this.toolStripStatusLabel1 = new System.Windows.Forms.ToolStripStatusLabel();
      this.toolStripStatusLabel2 = new System.Windows.Forms.ToolStripStatusLabel();
      this.menuStrip1 = new System.Windows.Forms.MenuStrip();
      this.fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
      this.mExit = new System.Windows.Forms.ToolStripMenuItem();
      this.editToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
      this.mIntersection = new System.Windows.Forms.ToolStripMenuItem();
      this.mUnion = new System.Windows.Forms.ToolStripMenuItem();
      this.mDifference = new System.Windows.Forms.ToolStripMenuItem();
      this.mXor = new System.Windows.Forms.ToolStripMenuItem();
      this.mNone = new System.Windows.Forms.ToolStripMenuItem();
      this.toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
      this.mEvenOdd = new System.Windows.Forms.ToolStripMenuItem();
      this.mNonZero = new System.Windows.Forms.ToolStripMenuItem();
      this.toolStripMenuItem2 = new System.Windows.Forms.ToolStripSeparator();
      this.mNewPath = new System.Windows.Forms.ToolStripMenuItem();
      this.mUndo = new System.Windows.Forms.ToolStripMenuItem();
      this.mClear = new System.Windows.Forms.ToolStripMenuItem();
      this.helpToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
      this.quickTipsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
      this.panel1 = new System.Windows.Forms.Panel();
      this.cbShowCtrls = new System.Windows.Forms.CheckBox();
      this.cbReconstBez = new System.Windows.Forms.CheckBox();
      this.bNewPath = new System.Windows.Forms.Button();
      this.rbClipPoly = new System.Windows.Forms.RadioButton();
      this.rbSubjPoly = new System.Windows.Forms.RadioButton();
      this.rbSubjBezier = new System.Windows.Forms.RadioButton();
      this.rbSubjLine = new System.Windows.Forms.RadioButton();
      this.groupBox1 = new System.Windows.Forms.GroupBox();
      this.DisplayPanel = new System.Windows.Forms.Panel();
      this.toolStripMenuItem3 = new System.Windows.Forms.ToolStripSeparator();
      this.mSave = new System.Windows.Forms.ToolStripMenuItem();
      this.mLoad = new System.Windows.Forms.ToolStripMenuItem();
      this.statusStrip1.SuspendLayout();
      this.menuStrip1.SuspendLayout();
      this.panel1.SuspendLayout();
      this.SuspendLayout();
      // 
      // statusStrip1
      // 
      this.statusStrip1.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.toolStripStatusLabel1,
            this.toolStripStatusLabel2});
      this.statusStrip1.Location = new System.Drawing.Point(0, 380);
      this.statusStrip1.Name = "statusStrip1";
      this.statusStrip1.Size = new System.Drawing.Size(623, 22);
      this.statusStrip1.TabIndex = 1;
      this.statusStrip1.Text = "statusStrip1";
      // 
      // toolStripStatusLabel1
      // 
      this.toolStripStatusLabel1.AutoSize = false;
      this.toolStripStatusLabel1.BorderSides = ((System.Windows.Forms.ToolStripStatusLabelBorderSides)((((System.Windows.Forms.ToolStripStatusLabelBorderSides.Left | System.Windows.Forms.ToolStripStatusLabelBorderSides.Top) 
            | System.Windows.Forms.ToolStripStatusLabelBorderSides.Right) 
            | System.Windows.Forms.ToolStripStatusLabelBorderSides.Bottom)));
      this.toolStripStatusLabel1.BorderStyle = System.Windows.Forms.Border3DStyle.SunkenOuter;
      this.toolStripStatusLabel1.Margin = new System.Windows.Forms.Padding(0, 3, 0, 0);
      this.toolStripStatusLabel1.Name = "toolStripStatusLabel1";
      this.toolStripStatusLabel1.Size = new System.Drawing.Size(110, 19);
      this.toolStripStatusLabel1.Text = "  Press F1 for Help";
      this.toolStripStatusLabel1.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      // 
      // toolStripStatusLabel2
      // 
      this.toolStripStatusLabel2.AutoSize = false;
      this.toolStripStatusLabel2.BorderSides = ((System.Windows.Forms.ToolStripStatusLabelBorderSides)((((System.Windows.Forms.ToolStripStatusLabelBorderSides.Left | System.Windows.Forms.ToolStripStatusLabelBorderSides.Top) 
            | System.Windows.Forms.ToolStripStatusLabelBorderSides.Right) 
            | System.Windows.Forms.ToolStripStatusLabelBorderSides.Bottom)));
      this.toolStripStatusLabel2.BorderStyle = System.Windows.Forms.Border3DStyle.SunkenOuter;
      this.toolStripStatusLabel2.Margin = new System.Windows.Forms.Padding(0, 3, 0, 0);
      this.toolStripStatusLabel2.Name = "toolStripStatusLabel2";
      this.toolStripStatusLabel2.Size = new System.Drawing.Size(300, 19);
      this.toolStripStatusLabel2.Text = "  Copyright 2013 - Angus Johnson";
      this.toolStripStatusLabel2.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      // 
      // menuStrip1
      // 
      this.menuStrip1.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem,
            this.editToolStripMenuItem,
            this.helpToolStripMenuItem});
      this.menuStrip1.Location = new System.Drawing.Point(0, 0);
      this.menuStrip1.Name = "menuStrip1";
      this.menuStrip1.Size = new System.Drawing.Size(623, 24);
      this.menuStrip1.TabIndex = 4;
      this.menuStrip1.Text = "menuStrip1";
      // 
      // fileToolStripMenuItem
      // 
      this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mSave,
            this.mLoad,
            this.toolStripMenuItem3,
            this.mExit});
      this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
      this.fileToolStripMenuItem.Size = new System.Drawing.Size(35, 20);
      this.fileToolStripMenuItem.Text = "&File";
      // 
      // mExit
      // 
      this.mExit.Name = "mExit";
      this.mExit.Size = new System.Drawing.Size(152, 22);
      this.mExit.Text = "E&xit  ";
      this.mExit.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      // 
      // editToolStripMenuItem
      // 
      this.editToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mIntersection,
            this.mUnion,
            this.mDifference,
            this.mXor,
            this.mNone,
            this.toolStripMenuItem1,
            this.mEvenOdd,
            this.mNonZero,
            this.toolStripMenuItem2,
            this.mNewPath,
            this.mUndo,
            this.mClear});
      this.editToolStripMenuItem.Name = "editToolStripMenuItem";
      this.editToolStripMenuItem.Size = new System.Drawing.Size(37, 20);
      this.editToolStripMenuItem.Text = "&Edit";
      // 
      // mIntersection
      // 
      this.mIntersection.Checked = true;
      this.mIntersection.CheckState = System.Windows.Forms.CheckState.Checked;
      this.mIntersection.Name = "mIntersection";
      this.mIntersection.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.I)));
      this.mIntersection.Size = new System.Drawing.Size(168, 22);
      this.mIntersection.Text = "&Intersection";
      this.mIntersection.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mIntersection.Click += new System.EventHandler(this.mClipType_Click);
      // 
      // mUnion
      // 
      this.mUnion.Name = "mUnion";
      this.mUnion.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.U)));
      this.mUnion.Size = new System.Drawing.Size(168, 22);
      this.mUnion.Text = "&Union";
      this.mUnion.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mUnion.Click += new System.EventHandler(this.mClipType_Click);
      // 
      // mDifference
      // 
      this.mDifference.Name = "mDifference";
      this.mDifference.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.D)));
      this.mDifference.Size = new System.Drawing.Size(168, 22);
      this.mDifference.Text = "&Difference";
      this.mDifference.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mDifference.Click += new System.EventHandler(this.mClipType_Click);
      // 
      // mXor
      // 
      this.mXor.Name = "mXor";
      this.mXor.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.X)));
      this.mXor.Size = new System.Drawing.Size(168, 22);
      this.mXor.Text = "&XOr";
      this.mXor.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mXor.Click += new System.EventHandler(this.mClipType_Click);
      // 
      // mNone
      // 
      this.mNone.Name = "mNone";
      this.mNone.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.Q)));
      this.mNone.Size = new System.Drawing.Size(168, 22);
      this.mNone.Text = "Non&e";
      this.mNone.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mNone.Click += new System.EventHandler(this.mClipType_Click);
      // 
      // toolStripMenuItem1
      // 
      this.toolStripMenuItem1.Name = "toolStripMenuItem1";
      this.toolStripMenuItem1.Size = new System.Drawing.Size(165, 6);
      // 
      // mEvenOdd
      // 
      this.mEvenOdd.Checked = true;
      this.mEvenOdd.CheckState = System.Windows.Forms.CheckState.Checked;
      this.mEvenOdd.Name = "mEvenOdd";
      this.mEvenOdd.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.E)));
      this.mEvenOdd.Size = new System.Drawing.Size(168, 22);
      this.mEvenOdd.Text = "&EvenOdd";
      this.mEvenOdd.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mEvenOdd.Click += new System.EventHandler(this.mFillType_Clicked);
      // 
      // mNonZero
      // 
      this.mNonZero.Name = "mNonZero";
      this.mNonZero.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.N)));
      this.mNonZero.Size = new System.Drawing.Size(168, 22);
      this.mNonZero.Text = "&NonZero";
      this.mNonZero.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mNonZero.Click += new System.EventHandler(this.mFillType_Clicked);
      // 
      // toolStripMenuItem2
      // 
      this.toolStripMenuItem2.Name = "toolStripMenuItem2";
      this.toolStripMenuItem2.Size = new System.Drawing.Size(165, 6);
      // 
      // mNewPath
      // 
      this.mNewPath.Name = "mNewPath";
      this.mNewPath.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.P)));
      this.mNewPath.Size = new System.Drawing.Size(168, 22);
      this.mNewPath.Text = "New &Path";
      this.mNewPath.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mNewPath.Click += new System.EventHandler(this.mNewPath_Click);
      // 
      // mUndo
      // 
      this.mUndo.Name = "mUndo";
      this.mUndo.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.Z)));
      this.mUndo.Size = new System.Drawing.Size(168, 22);
      this.mUndo.Text = "Und&o";
      this.mUndo.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mUndo.Click += new System.EventHandler(this.mUndo_Click);
      // 
      // mClear
      // 
      this.mClear.Name = "mClear";
      this.mClear.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Control | System.Windows.Forms.Keys.C)));
      this.mClear.Size = new System.Drawing.Size(168, 22);
      this.mClear.Text = "&Clear";
      this.mClear.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.mClear.Click += new System.EventHandler(this.mClear_Click);
      // 
      // helpToolStripMenuItem
      // 
      this.helpToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.quickTipsToolStripMenuItem});
      this.helpToolStripMenuItem.Name = "helpToolStripMenuItem";
      this.helpToolStripMenuItem.Size = new System.Drawing.Size(40, 20);
      this.helpToolStripMenuItem.Text = "&Help";
      // 
      // quickTipsToolStripMenuItem
      // 
      this.quickTipsToolStripMenuItem.Name = "quickTipsToolStripMenuItem";
      this.quickTipsToolStripMenuItem.ShortcutKeys = System.Windows.Forms.Keys.F1;
      this.quickTipsToolStripMenuItem.Size = new System.Drawing.Size(141, 22);
      this.quickTipsToolStripMenuItem.Text = "&Quick Tips";
      this.quickTipsToolStripMenuItem.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
      this.quickTipsToolStripMenuItem.Click += new System.EventHandler(this.quickTipsToolStripMenuItem_Click);
      // 
      // panel1
      // 
      this.panel1.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
      this.panel1.Controls.Add(this.cbShowCtrls);
      this.panel1.Controls.Add(this.cbReconstBez);
      this.panel1.Controls.Add(this.bNewPath);
      this.panel1.Controls.Add(this.rbClipPoly);
      this.panel1.Controls.Add(this.rbSubjPoly);
      this.panel1.Controls.Add(this.rbSubjBezier);
      this.panel1.Controls.Add(this.rbSubjLine);
      this.panel1.Controls.Add(this.groupBox1);
      this.panel1.Dock = System.Windows.Forms.DockStyle.Left;
      this.panel1.Location = new System.Drawing.Point(0, 24);
      this.panel1.Name = "panel1";
      this.panel1.Size = new System.Drawing.Size(159, 356);
      this.panel1.TabIndex = 5;
      // 
      // cbShowCtrls
      // 
      this.cbShowCtrls.AutoSize = true;
      this.cbShowCtrls.Enabled = false;
      this.cbShowCtrls.Location = new System.Drawing.Point(12, 255);
      this.cbShowCtrls.Name = "cbShowCtrls";
      this.cbShowCtrls.Size = new System.Drawing.Size(121, 17);
      this.cbShowCtrls.TabIndex = 21;
      this.cbShowCtrls.Text = "Show C&trl Points too";
      this.cbShowCtrls.UseVisualStyleBackColor = true;
      this.cbShowCtrls.Click += new System.EventHandler(this.cbShowCtrls_Click);
      // 
      // cbReconstBez
      // 
      this.cbReconstBez.AutoSize = true;
      this.cbReconstBez.Location = new System.Drawing.Point(12, 218);
      this.cbReconstBez.Name = "cbReconstBez";
      this.cbReconstBez.Size = new System.Drawing.Size(133, 17);
      this.cbReconstBez.TabIndex = 20;
      this.cbReconstBez.Text = "Reconstructed Beziers";
      this.cbReconstBez.UseVisualStyleBackColor = true;
      this.cbReconstBez.Click += new System.EventHandler(this.cbReconstBez_Click);
      // 
      // bNewPath
      // 
      this.bNewPath.Enabled = false;
      this.bNewPath.Location = new System.Drawing.Point(12, 157);
      this.bNewPath.Name = "bNewPath";
      this.bNewPath.Size = new System.Drawing.Size(130, 28);
      this.bNewPath.TabIndex = 19;
      this.bNewPath.Text = "New &Path";
      this.bNewPath.UseVisualStyleBackColor = true;
      this.bNewPath.Click += new System.EventHandler(this.mNewPath_Click);
      // 
      // rbClipPoly
      // 
      this.rbClipPoly.AutoSize = true;
      this.rbClipPoly.Location = new System.Drawing.Point(26, 108);
      this.rbClipPoly.Name = "rbClipPoly";
      this.rbClipPoly.Size = new System.Drawing.Size(83, 17);
      this.rbClipPoly.TabIndex = 16;
      this.rbClipPoly.TabStop = true;
      this.rbClipPoly.Text = "&Clip Polygon";
      this.rbClipPoly.UseVisualStyleBackColor = true;
      this.rbClipPoly.Click += new System.EventHandler(this.rbAdd_Click);
      // 
      // rbSubjPoly
      // 
      this.rbSubjPoly.AutoSize = true;
      this.rbSubjPoly.Location = new System.Drawing.Point(26, 85);
      this.rbSubjPoly.Name = "rbSubjPoly";
      this.rbSubjPoly.Size = new System.Drawing.Size(102, 17);
      this.rbSubjPoly.TabIndex = 14;
      this.rbSubjPoly.Text = "&Subject Polygon";
      this.rbSubjPoly.UseVisualStyleBackColor = true;
      this.rbSubjPoly.Click += new System.EventHandler(this.rbAdd_Click);
      // 
      // rbSubjBezier
      // 
      this.rbSubjBezier.AutoSize = true;
      this.rbSubjBezier.Location = new System.Drawing.Point(26, 62);
      this.rbSubjBezier.Name = "rbSubjBezier";
      this.rbSubjBezier.Size = new System.Drawing.Size(93, 17);
      this.rbSubjBezier.TabIndex = 13;
      this.rbSubjBezier.Text = "Subject &Bezier";
      this.rbSubjBezier.UseVisualStyleBackColor = true;
      this.rbSubjBezier.Click += new System.EventHandler(this.rbAdd_Click);
      // 
      // rbSubjLine
      // 
      this.rbSubjLine.AutoSize = true;
      this.rbSubjLine.Checked = true;
      this.rbSubjLine.Location = new System.Drawing.Point(26, 39);
      this.rbSubjLine.Name = "rbSubjLine";
      this.rbSubjLine.Size = new System.Drawing.Size(84, 17);
      this.rbSubjLine.TabIndex = 12;
      this.rbSubjLine.TabStop = true;
      this.rbSubjLine.Text = "Subject &Line";
      this.rbSubjLine.UseVisualStyleBackColor = true;
      this.rbSubjLine.Click += new System.EventHandler(this.rbAdd_Click);
      // 
      // groupBox1
      // 
      this.groupBox1.Location = new System.Drawing.Point(12, 20);
      this.groupBox1.Name = "groupBox1";
      this.groupBox1.Size = new System.Drawing.Size(130, 123);
      this.groupBox1.TabIndex = 18;
      this.groupBox1.TabStop = false;
      this.groupBox1.Text = "Add ...";
      // 
      // DisplayPanel
      // 
      this.DisplayPanel.BackColor = System.Drawing.SystemColors.Window;
      this.DisplayPanel.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
      this.DisplayPanel.Dock = System.Windows.Forms.DockStyle.Fill;
      this.DisplayPanel.Location = new System.Drawing.Point(159, 24);
      this.DisplayPanel.Name = "DisplayPanel";
      this.DisplayPanel.Size = new System.Drawing.Size(464, 356);
      this.DisplayPanel.TabIndex = 6;
      this.DisplayPanel.Paint += new System.Windows.Forms.PaintEventHandler(this.DisplayPanel_Paint);
      this.DisplayPanel.MouseDown += new System.Windows.Forms.MouseEventHandler(this.DisplayPanel_MouseDown);
      this.DisplayPanel.MouseMove += new System.Windows.Forms.MouseEventHandler(this.DisplayPanel_MouseMove);
      this.DisplayPanel.MouseUp += new System.Windows.Forms.MouseEventHandler(this.DisplayPanel_MouseUp);
      // 
      // toolStripMenuItem3
      // 
      this.toolStripMenuItem3.Name = "toolStripMenuItem3";
      this.toolStripMenuItem3.Size = new System.Drawing.Size(149, 6);
      // 
      // mSave
      // 
      this.mSave.Name = "mSave";
      this.mSave.Size = new System.Drawing.Size(152, 22);
      this.mSave.Text = "&Save";
      this.mSave.Click += new System.EventHandler(this.mSave_Click);
      // 
      // mLoad
      // 
      this.mLoad.Name = "mLoad";
      this.mLoad.Size = new System.Drawing.Size(152, 22);
      this.mLoad.Text = "&Load";
      this.mLoad.Click += new System.EventHandler(this.mLoad_Click);
      // 
      // MainForm
      // 
      this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
      this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
      this.ClientSize = new System.Drawing.Size(623, 402);
      this.Controls.Add(this.DisplayPanel);
      this.Controls.Add(this.panel1);
      this.Controls.Add(this.menuStrip1);
      this.Controls.Add(this.statusStrip1);
      this.KeyPreview = true;
      this.Name = "MainForm";
      this.Text = "C# Lines Demo";
      this.FormClosed += new System.Windows.Forms.FormClosedEventHandler(this.MainForm_FormClosed);
      this.Load += new System.EventHandler(this.MainForm_Load);
      this.KeyDown += new System.Windows.Forms.KeyEventHandler(this.MainForm_KeyDown);
      this.Resize += new System.EventHandler(this.MainForm_Resize);
      this.statusStrip1.ResumeLayout(false);
      this.statusStrip1.PerformLayout();
      this.menuStrip1.ResumeLayout(false);
      this.menuStrip1.PerformLayout();
      this.panel1.ResumeLayout(false);
      this.panel1.PerformLayout();
      this.ResumeLayout(false);
      this.PerformLayout();

    }

    #endregion

    private System.Windows.Forms.StatusStrip statusStrip1;
    private System.Windows.Forms.ToolStripStatusLabel toolStripStatusLabel1;
    private System.Windows.Forms.ToolStripStatusLabel toolStripStatusLabel2;
    private System.Windows.Forms.MenuStrip menuStrip1;
    private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
    private System.Windows.Forms.ToolStripMenuItem mExit;
    private System.Windows.Forms.ToolStripMenuItem editToolStripMenuItem;
    private System.Windows.Forms.ToolStripMenuItem mIntersection;
    private System.Windows.Forms.ToolStripMenuItem mUnion;
    private System.Windows.Forms.ToolStripMenuItem mDifference;
    private System.Windows.Forms.ToolStripMenuItem mXor;
    private System.Windows.Forms.ToolStripMenuItem mNone;
    private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
    private System.Windows.Forms.ToolStripMenuItem mEvenOdd;
    private System.Windows.Forms.ToolStripMenuItem mNonZero;
    private System.Windows.Forms.ToolStripSeparator toolStripMenuItem2;
    private System.Windows.Forms.ToolStripMenuItem mNewPath;
    private System.Windows.Forms.ToolStripMenuItem mUndo;
    private System.Windows.Forms.ToolStripMenuItem mClear;
    private System.Windows.Forms.ToolStripMenuItem helpToolStripMenuItem;
    private System.Windows.Forms.ToolStripMenuItem quickTipsToolStripMenuItem;
    private System.Windows.Forms.Panel panel1;
    private System.Windows.Forms.Button bNewPath;
    private System.Windows.Forms.RadioButton rbClipPoly;
    private System.Windows.Forms.RadioButton rbSubjPoly;
    private System.Windows.Forms.RadioButton rbSubjBezier;
    private System.Windows.Forms.RadioButton rbSubjLine;
    private System.Windows.Forms.GroupBox groupBox1;
    private System.Windows.Forms.Panel DisplayPanel;
    private System.Windows.Forms.CheckBox cbReconstBez;
    private System.Windows.Forms.CheckBox cbShowCtrls;
    private System.Windows.Forms.ToolStripMenuItem mSave;
    private System.Windows.Forms.ToolStripMenuItem mLoad;
    private System.Windows.Forms.ToolStripSeparator toolStripMenuItem3;
  }
}

